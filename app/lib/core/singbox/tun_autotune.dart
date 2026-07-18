/// Комбинация параметров TUN, которую перебирает автоподбор.
class TunCombo {
  /// null — не писать поле `stack` (дефолт ядра).
  final String? stack;
  final int mtu;
  const TunCombo(this.stack, this.mtu);

  String get label => '${stack ?? "дефолт ядра"}, MTU $mtu';

  Map<String, dynamic> toJson() => {'stack': stack, 'mtu': mtu};

  factory TunCombo.fromJson(Map<String, dynamic> j) =>
      TunCombo(j['stack'] as String?, (j['mtu'] as num?)?.toInt() ?? 1500);

  @override
  bool operator ==(Object other) =>
      other is TunCombo && other.stack == stack && other.mtu == mtu;

  @override
  int get hashCode => Object.hash(stack, mtu);
}

/// Подбор рабочих параметров TUN, когда пользователь выбрал стек «авто».
///
/// Раньше «авто» означало лишь «не писать поле stack» — то есть никакого подбора не
/// было, и при несовместимости стека с системой (антивирус, драйвер, MTU провайдера)
/// туннель просто не поднимался. Теперь перебираем комбинации, а удачную запоминаем,
/// чтобы в следующий раз она шла первой.
///
/// Порядок: сначала все стеки на «родном» MTU (стек — самая частая причина), затем
/// уменьшенные MTU (обрывы на больших пакетах: PPPoE, мобильный интернет, двойной NAT).
class TunAutotune {
  static const stacks = <String?>['system', 'gvisor', 'mixed'];
  static const mtus = <int>[1500, 1400, 1280];

  /// Комбинации для перебора. [preferred] (запомненная рабочая) идёт первой,
  /// [baseMtu] — MTU из настроек: он пробуется раньше уменьшенных.
  static List<TunCombo> combos({TunCombo? preferred, int baseMtu = 1500}) {
    final ordered = <TunCombo>[];
    void add(TunCombo c) {
      if (!ordered.contains(c)) ordered.add(c);
    }

    if (preferred != null) add(preferred);
    // Сначала перебор стеков на выбранном MTU.
    for (final s in stacks) {
      add(TunCombo(s, baseMtu));
    }
    // Затем уменьшенный MTU — на тех же стеках.
    for (final m in mtus) {
      if (m >= baseMtu) continue;
      for (final s in stacks) {
        add(TunCombo(s, m));
      }
    }
    return ordered;
  }
}
