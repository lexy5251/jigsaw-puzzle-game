/// Defines the images and grid sizes available on the selection screen.
/// PuzzleImage describes an image; PuzzleSize describes its piece layout.
/// Each image can be played with any of the listed sizes.
library;

/// A bundled puzzle photo.
class PuzzleImage {
  const PuzzleImage({
    required this.id,
    required this.title,
    required this.fileName,
  });

  /// Stable key for this image. Saved progress will reference it later,
  /// so never rename or reuse an id once released.
  final String id;

  final String title;

  /// File name under assets/images/.
  final String fileName;

  /// Full path for Flutter's Image.asset (Flame adds the prefix itself).
  String get assetPath => 'assets/images/$fileName';
}

/// A piece-count option: how the image is cut into a grid.
class PuzzleSize {
  const PuzzleSize({
    required this.label,
    required this.columns,
    required this.rows,
  });

  final String label;
  final int columns;
  final int rows;

  /// Getter: calculates the total when you read size.pieceCount, without ().
  int get pieceCount => columns * rows;
}

const puzzleSizes = [
  PuzzleSize(label: 'Easy', columns: 6, rows: 4),
  PuzzleSize(label: 'Medium', columns: 10, rows: 6),
  PuzzleSize(label: 'Hard', columns: 12, rows: 10),
];

const puzzleCatalog = [
  PuzzleImage(id: 'test-photo', title: 'Test Photo', fileName: 'test_photo.jpg'),
];
