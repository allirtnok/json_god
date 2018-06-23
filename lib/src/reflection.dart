library json_god.reflection;

import 'dart:mirrors';
import 'package:json_god/json_god.dart';

const Symbol hashCodeSymbol = #hashCode;
const Symbol runtimeTypeSymbol = #runtimeType;

typedef Serializer(value);
typedef Deserializer(value, {Type outputType});

List<Symbol> _findGetters(ClassMirror classMirror, bool debug) {
  List<Symbol> result = [];

  classMirror.instanceMembers
      .forEach((Symbol symbol, MethodMirror methodMirror) {
    if (methodMirror.isGetter &&
        symbol != hashCodeSymbol &&
        symbol != runtimeTypeSymbol) {
      if (debug) logger.info("Found getter on instance: $symbol");
      result.add(symbol);
    }
  });

  return result;
}

serialize(value, Serializer serializer, [@deprecated bool debug = false]) {
  logger.info("Serializing this value via reflection: $value");
  Map result = {};
  InstanceMirror instanceMirror = reflect(value);
  ClassMirror classMirror = instanceMirror.type;

  // Check for toJson
  for (Symbol symbol in classMirror.instanceMembers.keys) {
    if (symbol == #toJson) {
      logger.info("Running toJson...");
      var result = instanceMirror.invoke(symbol, []).reflectee;
      logger.info("Result of serialization via reflection: $result");
      return result;
    }
  }

  for (Symbol symbol in _findGetters(classMirror, debug)) {
    String name = MirrorSystem.getName(symbol);
    var valueForSymbol = instanceMirror.getField(symbol).reflectee;

    try {
      result[name] = serializer(valueForSymbol);
      logger.info("Set $name to $valueForSymbol");
    } catch (e, st) {
      logger.severe("Could not set $name to $valueForSymbol", e, st);
    }
  }

  logger.info("Result of serialization via reflection: $result");

  return result;
}

deserialize(value, Type outputType, Deserializer deserializer,
    [@deprecated bool debug = false]) {
  logger.info("About to deserialize $value to a $outputType");

  try {
    if (value is List) {
      List<TypeMirror> typeArguments = reflectType(outputType).typeArguments;

      Iterable it;

      if (typeArguments.isEmpty) {
        it = value.map(deserializer);
      } else {
        it = value.map((item) =>
            deserializer(item, outputType: typeArguments[0].reflectedType));
      }

      if (typeArguments.isEmpty) return it.toList();
      logger.info('Casting list elements to ${typeArguments[0].reflectedType}');
      var inv = new Invocation.genericMethod(#cast,
          [typeArguments[0].reflectedType], []);
      logger.info('INVOCATION OF ${inv.memberName} with type args: ${inv
          .typeArguments}');
      ClassMirror a;
      var output = reflect(it.toList()).delegate(inv);
      logger.info('Casted list type: ${output.runtimeType}');
      return output;
    } else if (value is Map)
      return _deserializeFromJsonByReflection(value, deserializer, outputType);
    else
      return deserializer(value);
  } catch (e, st) {
    logger.severe('Deserialization failed.', e, st);
    rethrow;
  }
}

/// Uses mirrors to deserialize an object.
_deserializeFromJsonByReflection(
    data, Deserializer deserializer, Type outputType,
    [@deprecated bool debug = false]) {
  // Check for fromJson
  var typeMirror = reflectType(outputType);

  var type = typeMirror as ClassMirror;
  var fromJson =
      new Symbol('${MirrorSystem.getName(type.simpleName)}.fromJson');

  for (Symbol symbol in type.declarations.keys) {
    if (symbol == fromJson) {
      var decl = type.declarations[symbol];

      if (decl is MethodMirror && decl.isConstructor) {
        logger.info("Running fromJson...");
        var result = type.newInstance(#fromJson, [data]).reflectee;

        logger.info("Result of deserialization via reflection: $result");
        return result;
      }
    }
  }

  ClassMirror classMirror = type;
  InstanceMirror instanceMirror = classMirror.newInstance(new Symbol(""), []);
  data.keys.forEach((key) {
    try {
      logger.info("Now deserializing value for $key");
      logger.info("data[\"$key\"] = ${data[key]}");
      var deserializedValue = deserializer(data[key]);

      logger.info("I want to set $key to the following ${deserializedValue
          .runtimeType}: $deserializedValue");
      // Get target type of getter
      Symbol searchSymbol = new Symbol(key);
      Symbol symbolForGetter =
          classMirror.instanceMembers.keys.firstWhere((x) => x == searchSymbol);
      Type requiredType =
          classMirror.instanceMembers[symbolForGetter].returnType.reflectedType;
      if (data[key].runtimeType != requiredType) {
        if (debug) {
          logger.info("Currently, $key is a ${data[key].runtimeType}.");
          logger.info("However, $key must be a $requiredType.");
        }

        deserializedValue =
            deserializer(deserializedValue, outputType: requiredType);
      }

      logger.info(
          "Final deserialized value for $key: $deserializedValue <${deserializedValue
              .runtimeType}>");
      instanceMirror.setField(new Symbol(key), deserializedValue);

      logger.info("Success! $key has been set to $deserializedValue");
    } catch (e, st) {
      logger.severe('Could not set value for field $key.', e, st);
    }
  });

  return instanceMirror.reflectee;
}
