import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// The three-way reading of an answer, the dotted field walk, and the slot bindings — each with the
/// case it exists to refuse.
void main() {
  group('readingOf', () {
    test('404 is the one status that means nothing stands there', () {
      expect(readingOf(answerOf(404), url: 'https://one.example/a'), isA<NothingThere>());
    });

    test('a JSON object in the two hundreds is held', () {
      final HttpReading reading = readingOf(
        answerOf(200, '{"state":"present"}'),
        url: 'https://one.example/a',
      );
      expect(reading, isA<AnswerHeld>());
      expect((reading as AnswerHeld).object['state'], 'present');
    });

    test('a failure never passes for absence', () {
      // The planted defect this guards: a 500 read as "nothing there", after which a request is
      // sent over whatever actually stands at the address.
      final HttpReading reading = readingOf(answerOf(500, 'boom'), url: 'https://one.example/a');
      expect(reading, isA<Unreadable>());
      expect((reading as Unreadable).because, contains('500'));
    });

    test('a body that is not a JSON object cannot be read a field out of', () {
      for (final String body in <String>['', 'not json', '[1,2]', '"text"']) {
        expect(readingOf(answerOf(200, body), url: 'https://one.example/a'), isA<Unreadable>());
      }
    });
  });

  group('fieldIn', () {
    const Map<String, Object?> object = <String, Object?>{
      'state': 'present',
      'count': 3,
      'live': true,
      'empty': null,
      'nested': <String, Object?>{'inner': 'deep'},
      'many': <Object?>[1, 2],
    };

    test('a dotted path descends one object per dot', () {
      expect((fieldIn(object, 'nested.inner') as FieldText).value, 'deep');
    });

    test('a number and a boolean are carried as text', () {
      expect((fieldIn(object, 'count') as FieldText).value, '3');
      expect((fieldIn(object, 'live') as FieldText).value, 'true');
    });

    test('a field that is not there, and one that holds nothing, are missing', () {
      expect(fieldIn(object, 'absent'), isA<FieldMissing>());
      expect(fieldIn(object, 'empty'), isA<FieldMissing>());
    });

    test('a list and an object are not one value', () {
      expect(fieldIn(object, 'many'), isA<FieldNotOneValue>());
      expect(fieldIn(object, 'nested'), isA<FieldNotOneValue>());
    });

    test('descending into a value that is not an object is refused, naming the segment', () {
      final FieldReading reading = fieldIn(object, 'state.deeper');
      expect(reading, isA<FieldNotOneValue>());
      expect((reading as FieldNotOneValue).because, contains('deeper'));
    });
  });

  group('slotSources', () {
    test('reads slot-name to {answer: name}', () {
      final Map<String, SlotSource> sources = slotSources(<String, Object?>{
        'api-host': <String, Object?>{'answer': 'api_host'},
      });
      expect(sources.keys, <String>['api-host']);
      expect((sources['api-host']! as SlotAnswer).answer, 'api_host');
    });

    test('nothing declared is nothing bound', () {
      expect(slotSources(null), isEmpty);
    });

    /// A row names {measured: name} and the framework writes the value in over that body before the
    /// step is built. Both shapes therefore reach this reader, at two different moments of one run,
    /// and neither may be refused: the body while nothing has published yet, the value once
    /// something has.
    test('a slot named for a measurement holds no value until the value is written in', () {
      expect(
        slotSources(<String, Object?>{
          'run-id': <String, Object?>{'measured': 'created_run_id'},
        }),
        isEmpty,
      );
      final Map<String, SlotSource> written = slotSources(<String, Object?>{'run-id': 'r_1'});
      expect((written['run-id']! as SlotWritten).value, 'r_1');
    });

    test('anything but a value, {answer: name} or {measured: name} is refused', () {
      expect(
        () => slotSources(<String, Object?>{
          'api-host': <String, Object?>{'answer': 'a', 'join': ','},
        }),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => slotSources(<String, Object?>{
          'api-host': <String, Object?>{'taken': 'a'},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('a slot no text spells is refused by name rather than ignored', () {
    expect(
      unusedSlotRefusal(<String, String>{'api-host': 'one.example'}, <String?>['https://x/', null]),
      contains('api-host'),
    );
    expect(
      unusedSlotRefusal(
        <String, String>{'api-host': 'one.example'},
        <String?>['https://<api-host>/'],
      ),
      isNull,
    );
  });

  test('an address still carrying a slot is refused with the slot in the sentence', () {
    expect(leftoverSlotRefusal('https://<api-host>/a'), contains('<api-host>'));
    expect(leftoverSlotRefusal('https://one.example/a'), isNull);
  });

  test('a credential rides the authorization header and a body its declared type', () {
    expect(composedHeaders(bearer: 's3cret', contentType: 'application/json'), <String, String>{
      'authorization': 'Bearer s3cret',
      'content-type': 'application/json',
    });
    expect(composedHeaders(), isEmpty);
  });
}
