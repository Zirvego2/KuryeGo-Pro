/// Firestore tam sayıları bazen [double] (ör. 4.0) döndürür; `as int` çökertir.
/// `int.tryParse(double.toString())` ise "4.0" için null verir — önce [num] olarak ele alınır.
int coerceFirestoreInt(dynamic value, [int defaultValue = 0]) {
  if (value == null) return defaultValue;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ?? defaultValue;
}

/// Alan Firestore'da yoksa veya `null` ise `null`; aksi halde güvenli [int].
int? coerceFirestoreIntOrNull(dynamic value) {
  if (value == null) return null;
  return coerceFirestoreInt(value);
}
