const bool tim2toxSoundToTextBackendSupported = false;

bool registerTim2toxSoundToTextIfSupported({
  required bool backendSupported,
  required bool alreadyRegistered,
  required bool pluginExists,
  required void Function() addPlugin,
}) {
  if (!backendSupported) return false;
  if (alreadyRegistered) return true;
  if (!pluginExists) addPlugin();
  return true;
}
