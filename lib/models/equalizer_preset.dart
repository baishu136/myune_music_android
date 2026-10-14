class EqualizerPreset {
  const EqualizerPreset(this.name, this.gains, {this.id});
  final String name;
  final List<double> gains;
  final String? id;
}
