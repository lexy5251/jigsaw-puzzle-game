/// Defines the images and grid sizes available on the selection screen.
/// PuzzleCategory groups images into themed collections shown as sections;
/// PuzzleImage describes an image; PuzzleSize describes its piece layout.
/// Each image can be played with any of the listed sizes.
library;

class PuzzleCategory {
  const PuzzleCategory({required this.id, required this.title});

  final String id;
  final String title;
}

/// Owner-made cover art for a category's card on the main page. These live
/// outside the catalog on purpose: covers never enter the game (owner
/// ruling, UI-3). A category without a cover file falls back to its first
/// catalog painting at the call site.
String categoryCoverPath(String categoryId) =>
    'assets/covers/$categoryId.jpg';

class PuzzleImage {
  const PuzzleImage({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.fileName,
  });

  /// Keep this ID stable when renaming the image or changing its title.
  final String id;
  final String title;
  final String categoryId;

  /// Relative to assets/images/; Flame adds that prefix automatically.
  final String fileName;

  /// Flutter needs the full asset path.
  String get assetPath => 'assets/images/$fileName';
}

class PuzzleSize {
  const PuzzleSize({required this.columns, required this.rows});

  final int columns;
  final int rows;

  int get pieceCount => columns * rows;
}

// Catalog images are square (1:1, since the 2026-11 regeneration), so
// grids stay square too — pieces are square only on such grids. Counts
// follow from that.
const puzzleSizes = [
  PuzzleSize(columns: 5, rows: 5),
  PuzzleSize(columns: 10, rows: 10),
  PuzzleSize(columns: 12, rows: 12),
  PuzzleSize(columns: 15, rows: 15),
];

const puzzleCategories = [
  PuzzleCategory(id: 'landscapes', title: 'Landscapes'),
  PuzzleCategory(id: 'cozy', title: 'Cozy Places'),
  PuzzleCategory(id: 'animals', title: 'Animals'),
  PuzzleCategory(id: 'flowers', title: 'Flowers & Gardens'),
  PuzzleCategory(id: 'cities', title: 'Cities & Travel'),
  PuzzleCategory(id: 'vintage_prints', title: 'Vintage Prints'),
  PuzzleCategory(id: 'art', title: 'Art & Patterns'),
];

const puzzleCatalog = [
  // -- Landscapes --
  PuzzleImage(
    id: 'alpine-lakes-panorama',
    title: 'Alpine Lake Morning',
    categoryId: 'landscapes',
    fileName: 'landscapes/alpine_lakes_panorama.webp',
  ),
  PuzzleImage(
    id: 'wild-coast-cliffs',
    title: 'Wild Coast Cliffs',
    categoryId: 'landscapes',
    fileName: 'landscapes/wild_coast_cliffs.webp',
  ),
  PuzzleImage(
    id: 'tuscan-sunset-hills',
    title: 'Tuscan Sunset Hills',
    categoryId: 'landscapes',
    fileName: 'landscapes/tuscan_sunset_hills.webp',
  ),
  PuzzleImage(
    id: 'fjord-village',
    title: 'Fjord Village',
    categoryId: 'landscapes',
    fileName: 'landscapes/fjord_village.webp',
  ),
  PuzzleImage(
    id: 'red-canyon-river',
    title: 'Red Canyon River',
    categoryId: 'landscapes',
    fileName: 'landscapes/red_canyon_river.webp',
  ),
  PuzzleImage(
    id: 'autumn-forest-path',
    title: 'Autumn Forest Path',
    categoryId: 'landscapes',
    fileName: 'landscapes/autumn_forest_path.webp',
  ),
  PuzzleImage(
    id: 'wildflower-meadow',
    title: 'Wildflower Meadow',
    categoryId: 'landscapes',
    fileName: 'landscapes/wildflower_meadow.webp',
  ),
  PuzzleImage(
    id: 'snowy-pine-valley',
    title: 'Snowy Pine Valley',
    categoryId: 'landscapes',
    fileName: 'landscapes/snowy_pine_valley.webp',
  ),
  PuzzleImage(
    id: 'lavender-field-evening',
    title: 'Lavender Field Evening',
    categoryId: 'landscapes',
    fileName: 'landscapes/lavender_field_evening.webp',
  ),
  PuzzleImage(
    id: 'mossy-waterfall-gorge',
    title: 'Waterfall Gorge',
    categoryId: 'landscapes',
    fileName: 'landscapes/mossy_waterfall_gorge.webp',
  ),
  // -- Cozy Places --
  PuzzleImage(
    id: 'country-stone-cottage',
    title: 'Country Stone Cottage',
    categoryId: 'cozy',
    fileName: 'cozy/country_stone_cottage.webp',
  ),
  PuzzleImage(
    id: 'fireplace-room',
    title: 'Fireplace Room',
    categoryId: 'cozy',
    fileName: 'cozy/fireplace_room.webp',
  ),
  PuzzleImage(
    id: 'reading-nook',
    title: 'Reading Nook',
    categoryId: 'cozy',
    fileName: 'cozy/reading_nook.webp',
  ),
  PuzzleImage(
    id: 'rainy-cafe-interior',
    title: 'Rainy Café Interior',
    categoryId: 'cozy',
    fileName: 'cozy/rainy_cafe_interior.webp',
  ),
  PuzzleImage(
    id: 'old-village-lane',
    title: 'Old Village Lane',
    categoryId: 'cozy',
    fileName: 'cozy/old_village_lane.webp',
  ),
  PuzzleImage(
    id: 'snowy-woodland-chalet',
    title: 'Snowy Woodland Chalet',
    categoryId: 'cozy',
    fileName: 'cozy/snowy_woodland_chalet.webp',
  ),
  PuzzleImage(
    id: 'farm-kitchen-morning',
    title: 'Farm Kitchen Morning',
    categoryId: 'cozy',
    fileName: 'cozy/farm_kitchen_morning.webp',
  ),
  PuzzleImage(
    id: 'greenhouse-corner',
    title: 'Greenhouse Corner',
    categoryId: 'cozy',
    fileName: 'cozy/greenhouse_corner.webp',
  ),
  PuzzleImage(
    id: 'attic-art-studio',
    title: 'Attic Art Studio',
    categoryId: 'cozy',
    fileName: 'cozy/attic_art_studio.webp',
  ),
  PuzzleImage(
    id: 'village-bakery-front',
    title: 'Village Bakery',
    categoryId: 'cozy',
    fileName: 'cozy/village_bakery_front.webp',
  ),
  // -- Animals --
  PuzzleImage(
    id: 'pets-in-the-reading-nook',
    title: 'Pets in the Reading Nook',
    categoryId: 'animals',
    fileName: 'animals/pets_in_the_reading_nook.webp',
  ),
  PuzzleImage(
    id: 'harbor-cat-at-dusk',
    title: 'Harbor Cat at Dusk',
    categoryId: 'animals',
    fileName: 'animals/harbor_cat_at_dusk.webp',
  ),
  PuzzleImage(
    id: 'dog-by-the-fire',
    title: 'Dog by the Fire',
    categoryId: 'animals',
    fileName: 'animals/dog_by_the_fire.webp',
  ),
  PuzzleImage(
    id: 'ducklings-pond-morning',
    title: 'Ducklings on the Pond',
    categoryId: 'animals',
    fileName: 'animals/ducklings_pond_morning.webp',
  ),
  PuzzleImage(
    id: 'garden-rabbits',
    title: 'Garden Rabbits',
    categoryId: 'animals',
    fileName: 'animals/garden_rabbits.webp',
  ),
  PuzzleImage(
    id: 'meadow-horses',
    title: 'Meadow Horses',
    categoryId: 'animals',
    fileName: 'animals/meadow_horses.webp',
  ),
  PuzzleImage(
    id: 'winter-fox',
    title: 'Winter Fox',
    categoryId: 'animals',
    fileName: 'animals/winter_fox.webp',
  ),
  PuzzleImage(
    id: 'bird-feeder-gathering',
    title: 'At the Bird Feeder',
    categoryId: 'animals',
    fileName: 'animals/bird_feeder_gathering.webp',
  ),
  PuzzleImage(
    id: 'hillside-sheep',
    title: 'Hillside Sheep',
    categoryId: 'animals',
    fileName: 'animals/hillside_sheep.webp',
  ),
  PuzzleImage(
    id: 'koi-pond-lanterns',
    title: 'Koi Pond',
    categoryId: 'animals',
    fileName: 'animals/koi_pond_lanterns.webp',
  ),
  // -- Flowers & Gardens --
  PuzzleImage(
    id: 'peony-bouquet',
    title: 'Peony Bouquet',
    categoryId: 'flowers',
    fileName: 'flowers/peony_bouquet.webp',
  ),
  PuzzleImage(
    id: 'tulips-and-windmill',
    title: 'Tulips & Windmill',
    categoryId: 'flowers',
    fileName: 'flowers/tulips_and_windmill.webp',
  ),
  PuzzleImage(
    id: 'wisteria-patio',
    title: 'Wisteria Patio',
    categoryId: 'flowers',
    fileName: 'flowers/wisteria_patio.webp',
  ),
  PuzzleImage(
    id: 'cherry-blossom-pond',
    title: 'Cherry Blossom Pond',
    categoryId: 'flowers',
    fileName: 'flowers/cherry_blossom_pond.webp',
  ),
  PuzzleImage(
    id: 'hydrangea-water-garden',
    title: 'Hydrangea Water Garden',
    categoryId: 'flowers',
    fileName: 'flowers/hydrangea_water_garden.webp',
  ),
  PuzzleImage(
    id: 'sunflower-field-noon',
    title: 'Sunflower Field',
    categoryId: 'flowers',
    fileName: 'flowers/sunflower_field_noon.webp',
  ),
  PuzzleImage(
    id: 'flower-market-stall',
    title: 'Flower Market Stall',
    categoryId: 'flowers',
    fileName: 'flowers/flower_market_stall.webp',
  ),
  PuzzleImage(
    id: 'windowsill-botanicals',
    title: 'Windowsill Botanicals',
    categoryId: 'flowers',
    fileName: 'flowers/windowsill_botanicals.webp',
  ),
  PuzzleImage(
    id: 'rose-arch-gate',
    title: 'Rose Arch Gate',
    categoryId: 'flowers',
    fileName: 'flowers/rose_arch_gate.webp',
  ),
  PuzzleImage(
    id: 'lavender-harvest-still-life',
    title: 'Lavender Harvest',
    categoryId: 'flowers',
    fileName: 'flowers/lavender_harvest_still_life.webp',
  ),
  // -- Cities & Travel --
  PuzzleImage(
    id: 'santorini-coast',
    title: 'Santorini Coast',
    categoryId: 'cities',
    fileName: 'cities/santorini_coast.webp',
  ),
  PuzzleImage(
    id: 'venice-canal',
    title: 'Venice Canal',
    categoryId: 'cities',
    fileName: 'cities/venice_canal.webp',
  ),
  PuzzleImage(
    id: 'paris-street',
    title: 'Paris Street',
    categoryId: 'cities',
    fileName: 'cities/paris_street.webp',
  ),
  PuzzleImage(
    id: 'london-riverside-dusk',
    title: 'London Riverside Dusk',
    categoryId: 'cities',
    fileName: 'cities/london_riverside_dusk.webp',
  ),
  PuzzleImage(
    id: 'amsterdam-canal-bikes',
    title: 'Amsterdam Canal',
    categoryId: 'cities',
    fileName: 'cities/amsterdam_canal_bikes.webp',
  ),
  PuzzleImage(
    id: 'japanese-temple-lane',
    title: 'Japanese Temple Lane',
    categoryId: 'cities',
    fileName: 'cities/japanese_temple_lane.webp',
  ),
  PuzzleImage(
    id: 'colorful-seaside-village',
    title: 'Colorful Seaside Village',
    categoryId: 'cities',
    fileName: 'cities/colorful_seaside_village.webp',
  ),
  PuzzleImage(
    id: 'old-town-charm',
    title: 'Old Town Flower Corner',
    categoryId: 'cities',
    fileName: 'cities/old_town_charm.webp',
  ),
  PuzzleImage(
    id: 'alpine-lakeside-village',
    title: 'Alpine Lakeside Village',
    categoryId: 'cities',
    fileName: 'cities/alpine_lakeside_village.webp',
  ),
  PuzzleImage(
    id: 'moroccan-blue-alley',
    title: 'Blue Alley',
    categoryId: 'cities',
    fileName: 'cities/moroccan_blue_alley.webp',
  ),
  // -- Vintage Prints --
  PuzzleImage(
    id: 'riviera-travel-poster',
    title: 'Riviera Poster',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/riviera_travel_poster.webp',
  ),
  PuzzleImage(
    id: 'alpine-train-poster',
    title: 'Alpine Train Poster',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/alpine_train_poster.webp',
  ),
  PuzzleImage(
    id: 'balloon-festival-poster',
    title: 'Balloon Festival',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/balloon_festival_poster.webp',
  ),
  PuzzleImage(
    id: 'botanical-rose-plate',
    title: 'Botanical Roses',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/botanical_rose_plate.webp',
  ),
  PuzzleImage(
    id: 'butterfly-specimen-plate',
    title: 'Butterflies & Moths',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/butterfly_specimen_plate.webp',
  ),
  PuzzleImage(
    id: 'orange-crate-label',
    title: 'Orange Grove Label',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/orange_crate_label.webp',
  ),
  PuzzleImage(
    id: 'retro-kitchen-still-life',
    title: 'Retro Kitchen',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/retro_kitchen_still_life.webp',
  ),
  PuzzleImage(
    id: 'vintage-teatime',
    title: 'Vintage Teatime',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/vintage_teatime.webp',
  ),
  PuzzleImage(
    id: 'sea-chart-voyage',
    title: 'Sea Chart Voyage',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/sea_chart_voyage.webp',
  ),
  PuzzleImage(
    id: 'flower-bicycle-print',
    title: 'Flower Bicycle',
    categoryId: 'vintage_prints',
    fileName: 'vintage_prints/flower_bicycle_print.webp',
  ),
  // -- Art & Patterns --
  PuzzleImage(
    id: 'cozy-craft-cabin',
    title: 'Cozy Craft Cabin',
    categoryId: 'art',
    fileName: 'art/cozy_craft_cabin.webp',
  ),
  PuzzleImage(
    id: 'storybook-mountain-train',
    title: 'Storybook Mountain Train',
    categoryId: 'art',
    fileName: 'art/storybook_mountain_train.webp',
  ),
  PuzzleImage(
    id: 'garden-bridge-in-bloom',
    title: 'Garden Bridge in Bloom',
    categoryId: 'art',
    fileName: 'art/garden_bridge_in_bloom.webp',
  ),
  PuzzleImage(
    id: 'lemon-terrace-cats',
    title: 'Lemon Terrace Cats',
    categoryId: 'art',
    fileName: 'art/lemon_terrace_cats.webp',
  ),
  PuzzleImage(
    id: 'seaside-carnival-pier',
    title: 'Seaside Carnival Pier',
    categoryId: 'art',
    fileName: 'art/seaside_carnival_pier.webp',
  ),
  PuzzleImage(
    id: 'teacup-harbor-town',
    title: 'Teacup Harbor Town',
    categoryId: 'art',
    fileName: 'art/teacup_harbor_town.webp',
  ),
  PuzzleImage(
    id: 'snowy-christmas-market',
    title: 'Snowy Christmas Market',
    categoryId: 'art',
    fileName: 'art/snowy_christmas_market.webp',
  ),
  PuzzleImage(
    id: 'winter-village-square',
    title: 'Winter Village Square',
    categoryId: 'art',
    fileName: 'art/winter_village_square.webp',
  ),
  PuzzleImage(
    id: 'retro-listening-room',
    title: 'Retro Listening Room',
    categoryId: 'art',
    fileName: 'art/retro_listening_room.webp',
  ),
  PuzzleImage(
    id: 'sunny-breakfast-kitchen',
    title: 'Sunny Breakfast Kitchen',
    categoryId: 'art',
    fileName: 'art/sunny_breakfast_kitchen.webp',
  ),
];

/// The images of one category, in catalog order. Tests pass a fixture
/// [catalog].
List<PuzzleImage> imagesInCategory(
  String categoryId, {
  List<PuzzleImage> catalog = puzzleCatalog,
}) => [
  for (final image in catalog)
    if (image.categoryId == categoryId) image,
];

/// The painting to offer as "Next puzzle" after finishing [current]: the
/// nearest image after it in its category (wrapping around) whose id is not
/// in [completedIds]. Null when the rest of the category is done — the
/// completion scene hides the button then.
PuzzleImage? nextPuzzleAfter(
  PuzzleImage current,
  Set<String> completedIds, {
  List<PuzzleImage> catalog = puzzleCatalog,
}) {
  final category = [
    for (final image in catalog)
      if (image.categoryId == current.categoryId) image,
  ];
  final start = category.indexWhere((image) => image.id == current.id);
  for (var step = 1; step <= category.length; step++) {
    final candidate = category[(start + step) % category.length];
    if (candidate.id != current.id && !completedIds.contains(candidate.id)) {
      return candidate;
    }
  }
  return null;
}
