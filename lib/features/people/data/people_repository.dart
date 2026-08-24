import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/api/envelope.dart';
import '../../../core/state/optimistic.dart';
import '../domain/person.dart';

class PeopleRepository {
  const PeopleRepository(this._api);

  final ApiClient _api;

  Future<List<Person>> list() async {
    final json = await _api.getJson(Endpoints.people);
    return Envelope.rows(json, const ['people']).map(Person.fromJson).toList();
  }

  /// [body] uses wire field names — see `Person.toWriteJson()`. The schema
  /// declares `name` and `relation` only; anything else is silently stripped.
  Future<Person> create(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.people, body: body);
    return Person.fromJson(Envelope.document(json, const ['person']));
  }

  Future<Person> update(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.person(id), body: body);
    return Person.fromJson(Envelope.document(json, const ['person']));
  }

  Future<void> delete(String id) => _api.deleteJson(Endpoints.person(id));

  /// Folds [id] into [intoId]: the duplicate's credits and splits move across
  /// and the duplicate is removed.
  ///
  /// The merge target's field name could not be confirmed against the live API
  /// (the recorded account has no people), so both spellings the backend might
  /// use go out together — Zod strips whichever it doesn't know. A mismatch
  /// surfaces as a field error on the sheet rather than a silent no-op.
  Future<void> merge(String id, String intoId) => _api.postJson(
    Endpoints.personMerge(id),
    body: {'into': intoId, 'target': intoId},
  );

  Future<List<PersonGroup>> groups() async {
    final json = await _api.getJson(Endpoints.peopleGroups);
    return Envelope.rows(json, const [
      'groups',
    ]).map(PersonGroup.fromJson).toList();
  }

  Future<PersonGroup> createGroup(Map<String, dynamic> body) async {
    final json = await _api.postJson(Endpoints.peopleGroups, body: body);
    return PersonGroup.fromJson(Envelope.document(json, const ['group']));
  }

  Future<PersonGroup> updateGroup(String id, Map<String, dynamic> body) async {
    final json = await _api.patchJson(Endpoints.personGroup(id), body: body);
    return PersonGroup.fromJson(Envelope.document(json, const ['group']));
  }

  Future<void> deleteGroup(String id) =>
      _api.deleteJson(Endpoints.personGroup(id));
}

final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(ref.watch(apiClientProvider)),
);

// ─── 6.4: the optimistic overlay ───────────────────────────────────────────
//
// The server's list moves to `<x>FetchProvider`; the public name stays on the
// composed view, so every existing `ref.watch` site gains optimism unedited.
// See lib/core/state/optimistic.dart.

/// The server's own list. Read this only to **refetch** it.
///
/// Session-cached: the credit sheet's person picker, the splits sheet and the
/// People screen all read it.
final peopleFetchProvider = FutureProvider<List<Person>>(
  (ref) => ref.watch(peopleRepositoryProvider).list(),
);

/// In-flight optimistic edits and deletes on `/people`.
///
/// `POST /people/:id/merge` is deliberately **not** routed through here — it
/// moves credits and splits across three collections and deletes the duplicate,
/// and the resulting rows are unknowable client-side. See
/// `PersonFormSheet._merge`.
final peopleWritesProvider =
    StateNotifierProvider<OptimisticCollection<Person>, PendingWrites<Person>>(
      (ref) => OptimisticCollection<Person>(idOf: (person) => person.id),
    );

final peopleProvider = Provider<AsyncValue<List<Person>>>(
  (ref) =>
      ref.watch(peopleWritesProvider).applyTo(ref.watch(peopleFetchProvider)),
);

/// The settle step for a people write.
Future<void> settlePeople(ProviderContainer container) =>
    settleFetch(container, peopleFetchProvider);

/// The server's own group list. Read this only to **refetch** it.
final personGroupsFetchProvider = FutureProvider<List<PersonGroup>>(
  (ref) => ref.watch(peopleRepositoryProvider).groups(),
);

/// In-flight optimistic edits and deletes on `/people/groups`.
final personGroupsWritesProvider =
    StateNotifierProvider<
      OptimisticCollection<PersonGroup>,
      PendingWrites<PersonGroup>
    >((ref) => OptimisticCollection<PersonGroup>(idOf: (group) => group.id));

final personGroupsProvider = Provider<AsyncValue<List<PersonGroup>>>(
  (ref) => ref
      .watch(personGroupsWritesProvider)
      .applyTo(ref.watch(personGroupsFetchProvider)),
);

/// The settle step for a groups write. Membership lives on both sides, so the
/// people list is dropped alongside.
Future<void> settlePersonGroups(ProviderContainer container) => settleFetch(
  container,
  personGroupsFetchProvider,
  also: [peopleFetchProvider],
);
