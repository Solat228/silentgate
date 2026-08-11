/// Перестановка элемента списка по правилам `ReorderableListView`.
///
/// ⚠️ ЛОВУШКА, РАДИ КОТОРОЙ ЭТО ОТДЕЛЬНАЯ ФУНКЦИЯ. Виджет отдаёт [newIndex],
/// посчитанный ДО изъятия элемента. Поэтому при движении ВНИЗ его нужно
/// уменьшить на единицу, а при движении вверх — нет. Без поправки элемент
/// встаёт на позицию раньше нужной, и со стороны это выглядит так, будто
/// список «не слушается»: тащишь на последнее место, а он встаёт предпоследним.
///
/// Возвращает НОВЫЙ список; исходный не меняется.
List<T> reordered<T>(List<T> items, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= items.length) return List<T>.of(items);
  var target = newIndex;
  if (target > oldIndex) target -= 1;
  if (target < 0) target = 0;
  if (target >= items.length) target = items.length - 1;
  final out = List<T>.of(items);
  if (target == oldIndex) return out;
  out.insert(target, out.removeAt(oldIndex));
  return out;
}
