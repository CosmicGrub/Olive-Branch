// OLIVE BRANCH — her colour: which fruit, vegetables and animals are which
// colour. No longer UNVERIFIED — verified by CI (a Flutter toolchain runs for
// real in tools/verify.sh's automated pipeline). MASTERFILE §8.6.5.
//
// The inventory behind Colour sort, Colour critter and Path code. Each colour
// has a few fruit, a few vegetables and a few animals; some colours lean on
// animals (there is almost no storm-grey fruit) and the activities say so
// plainly rather than inventing one. An item that is NOT that colour in real
// life is marked storybook (`real: false`) and the child app says so out loud
// ("a pretend purple elephant") — real and pretend are never mixed up.
//
// Names are plain nouns. There is no ranking, no "favourite", and nothing here
// is recorded about her: the list is a fact about the world, not about her.

class FoodItem {
  const FoodItem(this.name, this.art, this.group, {this.real = true});

  final String name;
  /// A recipe key in her_colour_art.dart.
  final String art;
  /// 'fruit' | 'veg' | 'animals'
  final String group;
  /// False = storybook: it is not this colour in real life.
  final bool real;

  /// What a voice or a label says, honest about pretend things.
  String get spoken => real ? name : 'a pretend ${name[0].toLowerCase()}${name.substring(1)}';
}

const List<String> foodGroups = ['fruit', 'veg', 'animals'];

const Map<String, String> foodGroupLabels = {'fruit': 'Fruit', 'veg': 'Vegetables', 'animals': 'Animals'};

FoodItem _f(String n, String a, {bool real = true}) => FoodItem(n, a, 'fruit', real: real);
FoodItem _v(String n, String a, {bool real = true}) => FoodItem(n, a, 'veg', real: real);
FoodItem _a(String n, String a, {bool real = true}) => FoodItem(n, a, 'animals', real: real);

final Map<String, List<FoodItem>> _inventory = {
  'sunny': [_f('Banana', 'banana'), _f('Lemon', 'round'), _f('Pineapple', 'round'),
    _v('Sweetcorn', 'longveg'), _v('Yellow pepper', 'round'),
    _a('Duckling', 'bird'), _a('Chick', 'bird'), _a('Bee', 'round-critter')],
  'tangerine': [_f('Orange', 'round'), _f('Mango', 'round'), _f('Apricot', 'round'),
    _v('Carrot', 'longveg'), _v('Pumpkin', 'round'), _v('Sweet potato', 'longveg'),
    _a('Fox', 'fox'), _a('Clownfish', 'fish'), _a('Orange cat', 'fox')],
  'coral': [_f('Peach', 'round'), _f('Pink grapefruit', 'round'), _f('Guava', 'round'),
    _v('Radish', 'round'), _v('Pink potato', 'longveg'),
    _a('Piglet', 'bear'), _a('Shrimp', 'fish'), _a('Coral fish', 'fish', real: false)],
  'bubblegum': [_f('Dragon fruit', 'round'), _f('Pink apple', 'round', real: false),
    _v('Beetroot', 'round'), _v('Radicchio', 'leafy'),
    _a('Flamingo', 'bird'), _a('Axolotl', 'bear'), _a('Pink dolphin', 'fish')],
  'grape': [_f('Grapes', 'cluster'), _f('Plum', 'round'), _f('Fig', 'round'),
    _v('Aubergine', 'longveg'), _v('Purple cabbage', 'leafy'), _v('Purple carrot', 'longveg'),
    _a('Purple elephant', 'elephant', real: false), _a('Purple hedgehog', 'bear', real: false)],
  'sea': [_f('Blueberries', 'cluster'), _f('Blue plum', 'round'),
    _v('Blue corn', 'longveg'), _v('Blue potato', 'longveg'),
    _a('Whale', 'fish'), _a('Blue tang', 'fish'), _a('Blue jay', 'bird')],
  'sky': [_f('Blueberry', 'cluster'), _f('Blue raspberry', 'cluster', real: false),
    _v('Blue cauliflower', 'leafy', real: false),
    _a('Bluebird', 'bird'), _a('Butterfly', 'bird'), _a('Cloud bunny', 'bear', real: false)],
  'mint': [_f('Honeydew', 'round'), _f('Green grapes', 'cluster'), _f('Kiwi', 'round'),
    _v('Cucumber', 'longveg'), _v('Celery', 'longveg'), _v('Peas', 'cluster'),
    _a('Sea turtle', 'bear'), _a('Budgie', 'bird')],
  'grass': [_f('Green apple', 'round'), _f('Pear', 'round'), _f('Lime', 'round'),
    _v('Broccoli', 'leafy'), _v('Spinach', 'leafy'), _v('Cucumber', 'longveg'),
    _a('Frog', 'frog'), _a('Caterpillar', 'cluster'), _a('Grasshopper', 'bird')],
  'chocolate': [_f('Coconut', 'round'), _f('Date', 'round'), _f('Chestnut', 'round'),
    _v('Potato', 'longveg'), _v('Mushroom', 'round'),
    _a('Bear cub', 'bear'), _a('Otter', 'bear'), _a('Hedgehog', 'bear')],
  'storm': [_v('Oyster mushroom', 'round'), _v('Kohlrabi', 'round'),
    _a('Elephant', 'elephant'), _a('Mouse', 'bear'), _a('Seal', 'fish')],
  'midnight': [_f('Blackberries', 'cluster'), _f('Black grapes', 'cluster'),
    _v('Black beans', 'cluster'), _v('Aubergine', 'longveg'),
    _a('Owl', 'bird'), _a('Bat', 'bear'), _a('Firefly', 'bird')],
};

/// Everything that is this colour, in a stable order: fruit, vegetables, animals.
List<FoodItem> foodsFor(String colourId, {List<String> groups = foodGroups}) {
  final all = _inventory[colourId] ?? const <FoodItem>[];
  return [for (final g in foodGroups) if (groups.contains(g)) ...all.where((i) => i.group == g)];
}

/// A short, even pool for a sorting round: up to [perGroup] from each group,
/// so no basket is empty unless the colour has nothing for it. Stable, so a
/// test (and a child who comes back to the same colour) sees the same nine.
List<FoodItem> sortPool(String colourId, {int perGroup = 3, List<String> groups = foodGroups}) {
  final all = foodsFor(colourId, groups: groups);
  return [for (final g in foodGroups) ...all.where((i) => i.group == g).take(perGroup)];
}

/// The animal she helps in Path code, and the food she walks to.
FoodItem pathHero(String colourId) {
  final all = foodsFor(colourId);
  return all.firstWhere((i) => i.group == 'animals' && i.real, orElse: () => const FoodItem('Fox', 'fox', 'animals'));
}

FoodItem pathGoal(String colourId) {
  final all = foodsFor(colourId);
  return all.firstWhere((i) => i.group != 'animals' && i.real, orElse: () => const FoodItem('Apple', 'round', 'fruit'));
}
