import 'package:flutter/widgets.dart';

/// Automation anchors of the location + People-nearby feature. Kept apart
/// from [UiKeys] (`ui_keys.dart` sits at its complexity pin); the strings are
/// the same kind of wire contract with out-of-process drivers.
class NearbyUiKeys {
  NearbyUiKeys._();

  // Location master switch + "visible to people nearby" (both default off).
  static const Key settingsLocationSwitch = Key('settings_location_switch');
  static const Key settingsNearbyVisibleSwitch = Key(
    'settings_nearby_visible_switch',
  );
  // People-nearby entry in the add-friend dialog and the page's list.
  static const Key addFriendNearbyButton = Key('add_friend_nearby_button');
  static const Key nearbyPeerList = Key('nearby_peer_list');
  // Composer attachment option that sends the current position.
  static const Key chatAttachLocationOption = Key('chat_attach_location_option');
  static const Key locationBubbleOpenMaps = Key('location_bubble_open_maps');
}
