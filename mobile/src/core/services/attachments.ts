import * as ImagePicker from 'expo-image-picker';
import { Platform } from 'react-native';

import { files } from './files';

/**
 * Image attachments for vision models. The picked file is copied out of the
 * picker's cache (which the system may clear at any time) into app storage,
 * so a message never points at an image that has vanished.
 */
export type PickSource = 'camera' | 'library';

export async function pickImage(source: PickSource): Promise<string | null> {
  const options: ImagePicker.ImagePickerOptions = {
    mediaTypes: ['images'],
    quality: 0.85,
    allowsEditing: source === 'camera',
  };
  let result: ImagePicker.ImagePickerResult;
  if (source === 'camera') {
    const perm = await ImagePicker.requestCameraPermissionsAsync();
    if (!perm.granted) return null;
    result = await ImagePicker.launchCameraAsync(options);
  } else {
    result = await ImagePicker.launchImageLibraryAsync(options);
  }
  const uri = result.canceled ? null : result.assets?.[0]?.uri;
  if (!uri) return null;
  if (Platform.OS === 'web') return uri;
  const dir = files.attachmentsDir();
  await files.mkdirp(dir);
  const ext = (uri.split('.').pop() ?? 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
  const dest = `${dir}/${Date.now()}.${ext}`;
  await files.copy(uri, dest);
  return dest;
}

export async function deleteAttachment(path: string | null): Promise<void> {
  if (path && Platform.OS !== 'web') await files.unlink(path);
}
