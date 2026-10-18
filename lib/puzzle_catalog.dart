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
  const PuzzleSize({
    required this.label,
    required this.columns,
    required this.rows,
  });

  final String label;
  final int columns;
  final int rows;

  int get pieceCount => columns * rows;
}

const puzzleSizes = [
  PuzzleSize(label: 'Easy', columns: 6, rows: 4),
  PuzzleSize(label: 'Medium', columns: 10, rows: 6),
  PuzzleSize(label: 'Hard', columns: 12, rows: 10),
];

const puzzleCategories = [
  PuzzleCategory(id: 'landscapes', title: 'Landscapes'),
  PuzzleCategory(id: 'cozy', title: 'Cozy Places'),
  PuzzleCategory(id: 'animals', title: 'Animals'),
  PuzzleCategory(id: 'flowers', title: 'Flowers & Gardens'),
  PuzzleCategory(id: 'cities', title: 'Cities & Travel'),
  PuzzleCategory(id: 'art', title: 'Art & Patterns'),
];

const puzzleCatalog = [
  // -- Landscapes --
  PuzzleImage(
    id: 'alpine-lakes-panorama',
    title: 'Alpine Lakes Panorama',
    categoryId: 'landscapes',
    fileName: 'landscapes/alpine_lakes_panorama.jpg',
  ),
  PuzzleImage(
    id: 'emerald-lake-vista',
    title: 'Emerald Lake Vista',
    categoryId: 'landscapes',
    fileName: 'landscapes/emerald_lake_vista.jpg',
  ),
  PuzzleImage(
    id: 'snowcapped-lake',
    title: 'Snowcapped Lake',
    categoryId: 'landscapes',
    fileName: 'landscapes/snowcapped_lake.jpg',
  ),
  PuzzleImage(
    id: 'wild-coast-cliffs',
    title: 'Wild Coast Cliffs',
    categoryId: 'landscapes',
    fileName: 'landscapes/wild_coast_cliffs.jpg',
  ),
  PuzzleImage(
    id: 'autumn-reflections',
    title: 'Autumn Reflections',
    categoryId: 'landscapes',
    fileName: 'landscapes/autumn_reflections.jpg',
  ),
  PuzzleImage(
    id: 'tuscan-sunset-hills',
    title: 'Tuscan Sunset Hills',
    categoryId: 'landscapes',
    fileName: 'landscapes/tuscan_sunset_hills.jpg',
  ),
  PuzzleImage(
    id: 'fjord-village',
    title: 'Fjord Village',
    categoryId: 'landscapes',
    fileName: 'landscapes/fjord_village.jpg',
  ),
  PuzzleImage(
    id: 'red-canyon-river',
    title: 'Red Canyon River',
    categoryId: 'landscapes',
    fileName: 'landscapes/red_canyon_river.jpg',
  ),
  PuzzleImage(
    id: 'turquoise-cove',
    title: 'Turquoise Cove',
    categoryId: 'landscapes',
    fileName: 'landscapes/turquoise_cove.jpg',
  ),
  PuzzleImage(
    id: 'wildflower-peaks',
    title: 'Wildflower Peaks',
    categoryId: 'landscapes',
    fileName: 'landscapes/wildflower_peaks.jpg',
  ),

  // -- Cozy Places --
  PuzzleImage(
    id: 'country-stone-cottage',
    title: 'Country Stone Cottage',
    categoryId: 'cozy',
    fileName: 'cozy/country_stone_cottage.jpg',
  ),
  PuzzleImage(
    id: 'forest-cabin',
    title: 'Forest Cabin',
    categoryId: 'cozy',
    fileName: 'cozy/forest_cabin.jpg',
  ),
  PuzzleImage(
    id: 'rainy-street-cafe',
    title: 'Rainy Street Café',
    categoryId: 'cozy',
    fileName: 'cozy/rainy_street_cafe.jpg',
  ),
  PuzzleImage(
    id: 'lakefront-cabin-deck',
    title: 'Lakefront Cabin Deck',
    categoryId: 'cozy',
    fileName: 'cozy/lakefront_cabin_deck.jpg',
  ),
  PuzzleImage(
    id: 'old-village-lane',
    title: 'Old Village Lane',
    categoryId: 'cozy',
    fileName: 'cozy/old_village_lane.jpg',
  ),
  PuzzleImage(
    id: 'snowy-woodland-chalet',
    title: 'Snowy Woodland Chalet',
    categoryId: 'cozy',
    fileName: 'cozy/snowy_woodland_chalet.jpg',
  ),
  PuzzleImage(
    id: 'rainy-cafe-interior',
    title: 'Rainy Café Interior',
    categoryId: 'cozy',
    fileName: 'cozy/rainy_cafe_interior.jpg',
  ),
  PuzzleImage(
    id: 'reading-nook',
    title: 'Reading Nook',
    categoryId: 'cozy',
    fileName: 'cozy/reading_nook.jpg',
  ),
  PuzzleImage(
    id: 'autumn-lake-cabin',
    title: 'Autumn Lake Cabin',
    categoryId: 'cozy',
    fileName: 'cozy/autumn_lake_cabin.jpg',
  ),
  PuzzleImage(
    id: 'fireplace-room',
    title: 'Fireplace Room',
    categoryId: 'cozy',
    fileName: 'cozy/fireplace_room.jpg',
  ),

  // -- Animals --
  PuzzleImage(
    id: 'city-window-cat-nap',
    title: 'City Window Cat Nap',
    categoryId: 'animals',
    fileName: 'animals/city_window_cat_nap.jpg',
  ),
  PuzzleImage(
    id: 'evening-cat-nap',
    title: 'Evening Cat Nap',
    categoryId: 'animals',
    fileName: 'animals/evening_cat_nap.jpg',
  ),
  PuzzleImage(
    id: 'golden-dreams',
    title: 'Golden Dreams',
    categoryId: 'animals',
    fileName: 'animals/golden_dreams.jpg',
  ),
  PuzzleImage(
    id: 'harbor-cat-at-dusk',
    title: 'Harbor Cat at Dusk',
    categoryId: 'animals',
    fileName: 'animals/harbor_cat_at_dusk.jpg',
  ),
  PuzzleImage(
    id: 'dog-by-the-fire',
    title: 'Dog by the Fire',
    categoryId: 'animals',
    fileName: 'animals/dog_by_the_fire.jpg',
  ),
  PuzzleImage(
    id: 'lakeside-camper-cat',
    title: 'Lakeside Camper Cat',
    categoryId: 'animals',
    fileName: 'animals/lakeside_camper_cat.jpg',
  ),
  PuzzleImage(
    id: 'cafe-companion',
    title: 'Café Companion',
    categoryId: 'animals',
    fileName: 'animals/cafe_companion.jpg',
  ),
  PuzzleImage(
    id: 'bookshop-nap',
    title: 'Bookshop Nap',
    categoryId: 'animals',
    fileName: 'animals/bookshop_nap.jpg',
  ),
  PuzzleImage(
    id: 'campfire-collie',
    title: 'Campfire Collie',
    categoryId: 'animals',
    fileName: 'animals/campfire_collie.jpg',
  ),
  PuzzleImage(
    id: 'lakeside-camp-dog',
    title: 'Lakeside Camp Dog',
    categoryId: 'animals',
    fileName: 'animals/lakeside_camp_dog.jpg',
  ),

  // -- Flowers & Gardens --
  PuzzleImage(
    id: 'rose-terrace-sunset',
    title: 'Rose Terrace Sunset',
    categoryId: 'flowers',
    fileName: 'flowers/rose_terrace_sunset.jpg',
  ),
  PuzzleImage(
    id: 'hydrangea-water-garden',
    title: 'Hydrangea Water Garden',
    categoryId: 'flowers',
    fileName: 'flowers/hydrangea_water_garden.jpg',
  ),
  PuzzleImage(
    id: 'peony-courtyard',
    title: 'Peony Courtyard',
    categoryId: 'flowers',
    fileName: 'flowers/peony_courtyard.jpg',
  ),
  PuzzleImage(
    id: 'wisteria-patio',
    title: 'Wisteria Patio',
    categoryId: 'flowers',
    fileName: 'flowers/wisteria_patio.jpg',
  ),
  PuzzleImage(
    id: 'garden-arch-view',
    title: 'Garden Arch View',
    categoryId: 'flowers',
    fileName: 'flowers/garden_arch_view.jpg',
  ),
  PuzzleImage(
    id: 'tulips-and-windmill',
    title: 'Tulips & Windmill',
    categoryId: 'flowers',
    fileName: 'flowers/tulips_and_windmill.jpg',
  ),
  PuzzleImage(
    id: 'cherry-blossom-pond',
    title: 'Cherry Blossom Pond',
    categoryId: 'flowers',
    fileName: 'flowers/cherry_blossom_pond.jpg',
  ),
  PuzzleImage(
    id: 'cottage-garden-sunset',
    title: 'Cottage Garden Sunset',
    categoryId: 'flowers',
    fileName: 'flowers/cottage_garden_sunset.jpg',
  ),
  PuzzleImage(
    id: 'peony-bouquet',
    title: 'Peony Bouquet',
    categoryId: 'flowers',
    fileName: 'flowers/peony_bouquet.jpg',
  ),
  PuzzleImage(
    id: 'poppy-meadow-sunset',
    title: 'Poppy Meadow Sunset',
    categoryId: 'flowers',
    fileName: 'flowers/poppy_meadow_sunset.jpg',
  ),

  // -- Cities & Travel --
  PuzzleImage(
    id: 'old-town-charm',
    title: 'Old Town Charm',
    categoryId: 'cities',
    fileName: 'cities/old_town_charm.jpg',
  ),
  PuzzleImage(
    id: 'santorini-coast',
    title: 'Santorini Coast',
    categoryId: 'cities',
    fileName: 'cities/santorini_coast.jpg',
  ),
  PuzzleImage(
    id: 'roman-architecture',
    title: 'Roman Architecture',
    categoryId: 'cities',
    fileName: 'cities/roman_architecture.jpg',
  ),
  PuzzleImage(
    id: 'venice-canal',
    title: 'Venice Canal',
    categoryId: 'cities',
    fileName: 'cities/venice_canal.jpg',
  ),
  PuzzleImage(
    id: 'japanese-landmark',
    title: 'Japanese Landmark',
    categoryId: 'cities',
    fileName: 'cities/japanese_landmark.jpg',
  ),
  PuzzleImage(
    id: 'london-riverside-dusk',
    title: 'London Riverside Dusk',
    categoryId: 'cities',
    fileName: 'cities/london_riverside_dusk.jpg',
  ),
  PuzzleImage(
    id: 'colorful-seaside-village',
    title: 'Colorful Seaside Village',
    categoryId: 'cities',
    fileName: 'cities/colorful_seaside_village.jpg',
  ),
  PuzzleImage(
    id: 'paris-street',
    title: 'Paris Street',
    categoryId: 'cities',
    fileName: 'cities/paris_street.jpg',
  ),
  PuzzleImage(
    id: 'adriatic-old-city',
    title: 'Adriatic Old City',
    categoryId: 'cities',
    fileName: 'cities/adriatic_old_city.jpg',
  ),
  PuzzleImage(
    id: 'alpine-lakeside-village',
    title: 'Alpine Lakeside Village',
    categoryId: 'cities',
    fileName: 'cities/alpine_lakeside_village.jpg',
  ),

  // -- Art & Patterns --
  PuzzleImage(
    id: 'cozy-craft-cabin',
    title: 'Cozy Craft Cabin',
    categoryId: 'art',
    fileName: 'art/cozy_craft_cabin.jpg',
  ),
  PuzzleImage(
    id: 'storybook-mountain-train',
    title: 'Storybook Mountain Train',
    categoryId: 'art',
    fileName: 'art/storybook_mountain_train.jpg',
  ),
  PuzzleImage(
    id: 'garden-bridge-in-bloom',
    title: 'Garden Bridge in Bloom',
    categoryId: 'art',
    fileName: 'art/garden_bridge_in_bloom.jpg',
  ),
  PuzzleImage(
    id: 'lemon-terrace-cats',
    title: 'Lemon Terrace Cats',
    categoryId: 'art',
    fileName: 'art/lemon_terrace_cats.jpg',
  ),
  PuzzleImage(
    id: 'seaside-carnival-pier',
    title: 'Seaside Carnival Pier',
    categoryId: 'art',
    fileName: 'art/seaside_carnival_pier.jpg',
  ),
  PuzzleImage(
    id: 'teacup-harbor-town',
    title: 'Teacup Harbor Town',
    categoryId: 'art',
    fileName: 'art/teacup_harbor_town.jpg',
  ),
  PuzzleImage(
    id: 'snowy-christmas-market',
    title: 'Snowy Christmas Market',
    categoryId: 'art',
    fileName: 'art/snowy_christmas_market.jpg',
  ),
  PuzzleImage(
    id: 'winter-village-square',
    title: 'Winter Village Square',
    categoryId: 'art',
    fileName: 'art/winter_village_square.jpg',
  ),
  PuzzleImage(
    id: 'retro-listening-room',
    title: 'Retro Listening Room',
    categoryId: 'art',
    fileName: 'art/retro_listening_room.jpg',
  ),
  PuzzleImage(
    id: 'sunny-breakfast-kitchen',
    title: 'Sunny Breakfast Kitchen',
    categoryId: 'art',
    fileName: 'art/sunny_breakfast_kitchen.jpg',
  ),
];

/// The images of one category, in catalog order.
List<PuzzleImage> imagesInCategory(String categoryId) => [
  for (final image in puzzleCatalog)
    if (image.categoryId == categoryId) image,
];
