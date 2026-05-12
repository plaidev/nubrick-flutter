enum EventPayloadType { integer, string, timestamp, unknown }

class EventPayload {
  final String name;
  final String value;
  final EventPayloadType type;
  EventPayload(this.name, this.value, this.type);
}

class Event {
  final String? name;
  final String? deepLink;
  final List<EventPayload>? payload;
  Event(this.name, this.deepLink, this.payload);
}

typedef EventHandler = void Function(Event event);
