class Event {
  final String id;
  final String title;

  Event({required this.id, required this.title});

  factory Event.fromMap(String id, Map<String, dynamic> data) {
    return Event(id: id, title: data['title']);
  }
}
