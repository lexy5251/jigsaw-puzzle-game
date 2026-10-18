# Image assets

Puzzle images live in `images/<category>/<descriptive_name>.jpg`.
Use lowercase words separated by underscores, without sequence numbers or
redundant category prefixes. For example: `images/animals/city_window_cat_nap.jpg`.

| Folder | Contents |
| --- | --- |
| `animals` | Cats, dogs, and other animals |
| `art` | Illustrations and artistic scenes |
| `cities` | City streets, landmarks, and travel scenes |
| `cozy` | Cabins, cafes, and comfortable interiors |
| `flowers` | Flowers, bouquets, and gardens |
| `landscapes` | Mountains, lakes, coastlines, and countryside |

Register each puzzle image in `lib/puzzle_catalog.dart`. The catalog controls
display titles and order; filenames do not need numeric prefixes. Update its
`fileName` whenever you rename an image, and keep existing image IDs stable.
New category folders also need an asset entry in `pubspec.yaml`.

`images/test_photo.jpg` is the shared image fixture used by game tests.
