import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/system_album.dart';
import '../../core/storage/local_storage_service.dart';

/// Where saving puts images; the gallery holds favorites only.
final systemAlbumProvider = Provider<SystemAlbum>(
  (ref) => SystemAlbum(storage: ref.read(localStorageServiceProvider)),
);
