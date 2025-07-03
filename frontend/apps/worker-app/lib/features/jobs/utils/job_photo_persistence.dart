import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A utility class to handle the persistence of photos taken during a job.
class JobPhotoPersistence {
  static const _kInProgressJobIdKey = 'in_progress_job_id';
  static String _photoListKey(String instanceId) =>
      'in_progress_photos_$instanceId';

  /// Gets the directory for storing photos for a specific job instance.
  static Future<Directory> _getJobPhotoDirectory(String instanceId) async {
    final appDocsDir = await getApplicationDocumentsDirectory();
    final jobPhotoDir =
        Directory(p.join(appDocsDir.path, 'job_photos', instanceId));
    if (!await jobPhotoDir.exists()) {
      await jobPhotoDir.create(recursive: true);
    }
    return jobPhotoDir;
  }

  /// Saves a new photo for the given job instance.
  /// It copies the file from a temporary location to a persistent one.
  static Future<XFile> savePhoto(String instanceId, XFile photoToSave) async {
    final prefs = await SharedPreferences.getInstance();
    final jobPhotoDir = await _getJobPhotoDirectory(instanceId);

    // Create a new file path in our persistent directory
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newPath = p.join(jobPhotoDir.path, '$timestamp.jpg');

    // Copy the file from the temp location to our new path.
    final newFile = await File(photoToSave.path).copy(newPath);

    // Update SharedPreferences with the new persistent path
    final currentPhotoPaths =
        prefs.getStringList(_photoListKey(instanceId)) ?? [];
    currentPhotoPaths.add(newFile.path);
    await prefs.setStringList(_photoListKey(instanceId), currentPhotoPaths);

    // Also store which job is currently in progress. This helps with cleanup.
    await prefs.setString(_kInProgressJobIdKey, instanceId);

    // Return a new XFile pointing to the persistent path
    return XFile(newFile.path);
  }

  /// Loads all saved photo paths for a job and returns them as XFiles.
  static Future<List<XFile>> loadPhotos(String instanceId) async {
    final prefs = await SharedPreferences.getInstance();
    final photoPaths = prefs.getStringList(_photoListKey(instanceId)) ?? [];

    final loadedPhotos = <XFile>[];
    for (final path in photoPaths) {
      // Check if file still exists before adding it
      if (await File(path).exists()) {
        loadedPhotos.add(XFile(path));
      }
    }
    return loadedPhotos;
  }

  /// Clears all saved photos and preferences for a job instance.
  static Future<void> clearPhotos(String instanceId) async {
    final prefs = await SharedPreferences.getInstance();
    final jobPhotoDir = await _getJobPhotoDirectory(instanceId);

    // Delete the directory and all its contents
    if (await jobPhotoDir.exists()) {
      await jobPhotoDir.delete(recursive: true);
    }

    // Remove the preference keys
    await prefs.remove(_photoListKey(instanceId));

    // If this was the currently active job, clear that key too.
    if (prefs.getString(_kInProgressJobIdKey) == instanceId) {
      await prefs.remove(_kInProgressJobIdKey);
    }
  }

  /// A cleanup utility to run on app start to remove orphaned photo directories
  /// for jobs that were completed or cancelled while the app was closed.
  static Future<void> cleanupOrphanedPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final activeJobId = prefs.getString(_kInProgressJobIdKey);

    final appDocsDir = await getApplicationDocumentsDirectory();
    final allPhotosBaseDir = Directory(p.join(appDocsDir.path, 'job_photos'));

    if (!await allPhotosBaseDir.exists()) return;

    final jobDirs = allPhotosBaseDir.listSync();
    for (final dir in jobDirs) {
      if (dir is Directory) {
        final dirName = p.basename(dir.path);
        // Delete any directory that isn't the currently active one
        if (dirName != activeJobId) {
          await dir.delete(recursive: true);
          // Also clear its prefs key just in case it's an orphan
          await prefs.remove(_photoListKey(dirName));
        }
      }
    }
  }
}
