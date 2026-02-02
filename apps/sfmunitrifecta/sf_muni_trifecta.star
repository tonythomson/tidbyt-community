"""
Applet: SF Muni Trifecta
Summary: Three Muni stops at once
Description: Monitor three SF Muni stops on a single screen.
Author: Tony
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# 511.org API endpoint
PREDICTIONS_URL = "https://api.511.org/transit/StopMonitoring?api_key=%s&agency=SF&stopCode=%s&format=json"

# Colors
COLOR_DIRECTION = "#CCC"  # Light gray for IN/OUT
COLOR_TIMES = "#D4A017"  # Muted gold for arrival times
COLOR_ROUTE1_BG = "#008752"  # Green background for first route
COLOR_ROUTE1_TEXT = "#FFF"  # White text on green
COLOR_ROUTE2_BG = "#00539b"  # Blue background for second route
COLOR_ROUTE2_TEXT = "#FFF"  # White text on blue

def main(config):
    api_key = config.get("api_key")
    if not api_key:
        return render.Root(
            child = render.Box(
                render.WrappedText(
                    content = "Set API key in config",
                    font = "tom-thumb",
                ),
            ),
        )

    # Get route and stop configuration
    route1 = config.get("route1") or ""
    stop1_in = config.get("stop1_in") or ""
    stop1_out = config.get("stop1_out") or ""
    route2 = config.get("route2") or ""
    stop2_in = config.get("stop2_in") or ""

    if not route1 or not stop1_in:
        return render.Root(
            child = render.Box(
                render.WrappedText(
                    content = "Configure stops",
                    font = "tom-thumb",
                ),
            ),
        )

    # Fetch predictions for each configured stop
    rows = []

    if route1 and stop1_in:
        predictions = get_predictions(api_key, stop1_in, route1)
        rows.append(render_row(route1, "IN", predictions, COLOR_ROUTE1_BG, COLOR_ROUTE1_TEXT))

    if route1 and stop1_out:
        predictions = get_predictions(api_key, stop1_out, route1)
        rows.append(render_row(route1, "OUT", predictions, COLOR_ROUTE1_BG, COLOR_ROUTE1_TEXT))

    if route2 and route2 != "none" and stop2_in:
        predictions = get_predictions(api_key, stop2_in, route2)
        rows.append(render_row(route2, "IN", predictions, COLOR_ROUTE2_BG, COLOR_ROUTE2_TEXT))

    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "space_evenly",
            children = rows,
        ),
    )

def get_predictions(api_key, stop_id, route_filter):
    """Fetch and parse predictions for a stop, filtered by route."""
    url = PREDICTIONS_URL % (api_key, stop_id)
    res = http.get(
        url,
        ttl_seconds = 60,
        headers = {"Accept-Encoding": "identity"},
    )

    if res.status_code != 200:
        print("API request failed: %d" % res.status_code)
        return []

    body = res.body().lstrip("\ufeff")

    data = json.decode(body)

    delivery = data.get("ServiceDelivery", {})
    monitoring = delivery.get("StopMonitoringDelivery", {})
    if not monitoring:
        return []

    visits = monitoring.get("MonitoredStopVisit", [])
    if not visits:
        return []

    predictions = []
    now = time.now().unix

    for visit in visits:
        journey = visit.get("MonitoredVehicleJourney", {})
        line = journey.get("LineRef")

        if line != route_filter:
            continue

        call = journey.get("MonitoredCall", {})
        expected = call.get("ExpectedDepartureTime") or call.get("ExpectedArrivalTime")

        if not expected:
            continue

        expected_time = time.parse_time(expected)
        if expected_time:
            minutes = int((expected_time.unix - now) / 60)
            if minutes >= 0:
                predictions.append(minutes)

    return sorted(predictions)[:3]

def render_row(route, direction, predictions, circle_color, text_color):
    """Render a single row: route, direction, and times."""

    if predictions:
        times_str = ", ".join([str(m) for m in predictions])
    else:
        times_str = "--"

    return render.Padding(
        pad = (2, 0, 0, 0),
        child = render.Row(
            expanded = True,
            main_align = "start",
            cross_align = "center",
            children = [
                render.Circle(
                    diameter = 9,
                    color = circle_color,
                    child = render.Text(route, font = "tom-thumb", color = text_color),
                ),
                render.Box(width = 2, height = 1),
                render.Box(
                    width = 20,
                    height = 8,
                    child = render.Text(direction, color = COLOR_DIRECTION),
                ),
                render.Text(times_str, color = COLOR_TIMES),
            ],
        ),
    )

def get_schema():
    route_options = [
        schema.Option(display = "N Judah", value = "N"),
        schema.Option(display = "J Church", value = "J"),
        schema.Option(display = "K Ingleside", value = "K"),
        schema.Option(display = "L Taraval", value = "L"),
        schema.Option(display = "M Ocean View", value = "M"),
        schema.Option(display = "T Third Street", value = "T"),
        schema.Option(display = "F Market", value = "F"),
        schema.Option(display = "1 California", value = "1"),
        schema.Option(display = "5 Fulton", value = "5"),
        schema.Option(display = "14 Mission", value = "14"),
        schema.Option(display = "22 Fillmore", value = "22"),
        schema.Option(display = "38 Geary", value = "38"),
        schema.Option(display = "38R Geary Rapid", value = "38R"),
        schema.Option(display = "49 Van Ness/Mission", value = "49"),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_key",
                name = "511.org API Key",
                desc = "Get free key at 511.org/open-data/token",
                icon = "key",
            ),
            schema.Dropdown(
                id = "route1",
                name = "Primary Route",
                desc = "Your main route",
                icon = "bus",
                options = route_options,
                default = "N",
            ),
            schema.Text(
                id = "stop1_in",
                name = "Inbound Stop Code",
                desc = "Find codes at 511.org/transit/agencies/stop-id",
                icon = "arrowRight",
            ),
            schema.Text(
                id = "stop1_out",
                name = "Outbound Stop Code",
                desc = "Find codes at 511.org/transit/agencies/stop-id",
                icon = "arrowLeft",
            ),
            schema.Dropdown(
                id = "route2",
                name = "Secondary Route",
                desc = "Optional second route",
                icon = "bus",
                options = [schema.Option(display = "None", value = "none")] + route_options,
                default = "none",
            ),
            schema.Text(
                id = "stop2_in",
                name = "Secondary Stop Code",
                desc = "Stop code for secondary route",
                icon = "mapPin",
            ),
        ],
    )
