# Toxee always selects tim2tox_ffi before initializing the Dart SDK (see
# LoggingBootstrap.initialize). The vendor Windows plugin is only an empty
# registration shim; its bundled ImSDK/dart_native_imsdk binaries are x64-only
# and are neither the selected FFI runtime nor native plugin dependencies.
# Keep the shim for Flutter's generated registrar, but do not link or distribute
# the unused Tencent runtime on either Windows architecture.
function(toxee_use_tim2tox_windows_sdk)
  if(NOT "tencent_cloud_chat_sdk" IN_LIST FLUTTER_PLUGIN_LIST)
    return()
  endif()
  if(NOT TARGET tencent_cloud_chat_sdk_plugin)
    message(FATAL_ERROR "Missing tencent_cloud_chat_sdk_plugin target. "
      "Re-review the Tox-only SDK policy in windows/cmake/tox_sdk.cmake.")
  endif()

  get_target_property(_sdk_dir tencent_cloud_chat_sdk_plugin SOURCE_DIR)
  # Fail closed when the reviewed, no-op native registration code changes.
  # A future vendor implementation may load ImSDK dynamically without a linker
  # reference. Normalize checkout line endings before hashing on Windows.
  set(_reviewed_sources
    "CMakeLists.txt=f594212fb37f556099fe076041128e43080614e38093880ab99f0d03defcedcd"
    "tencent_cloud_chat_sdk_plugin.cpp=be7f36df2071391f2a2c9e32dff83f2033d54b87263d725cb6923555dc362568"
    "tencent_cloud_chat_sdk_plugin.h=3ce404e04e7ab9472903f3632b94cfdf1a353d5f2c38bd5df752ebfb06a8baf9"
    "tencent_cloud_chat_sdk_plugin_c_api.cpp=8d658010a75e5e322e373f78d21f020b895f16e01b55cd306dc563594d801bc3"
    "include/tencent_cloud_chat_sdk/tencent_cloud_chat_sdk_plugin_c_api.h=419bf0b68e63e7dbd83011a1fa9b5c8160e39038be57a2c58c93cc56fccce43e")
  foreach(_entry IN LISTS _reviewed_sources)
    string(REPLACE "=" ";" _pair "${_entry}")
    list(GET _pair 0 _source)
    list(GET _pair 1 _expected_hash)
    if(NOT EXISTS "${_sdk_dir}/${_source}")
      message(FATAL_ERROR "Missing SDK native source ${_source}. "
        "Re-review the Tox-only SDK policy in windows/cmake/tox_sdk.cmake.")
    endif()
    file(READ "${_sdk_dir}/${_source}" _contents)
    string(REPLACE "\r\n" "\n" _contents "${_contents}")
    string(SHA256 _actual_hash "${_contents}")
    if(NOT _actual_hash STREQUAL _expected_hash)
      message(FATAL_ERROR "SDK native source changed: ${_source}. "
        "Re-review the Tox-only SDK policy in windows/cmake/tox_sdk.cmake.")
    endif()
  endforeach()

  get_target_property(_sdk_links tencent_cloud_chat_sdk_plugin LINK_LIBRARIES)
  set(_vendor_import "${_sdk_dir}/lib/ImSDK.lib")
  set(_vendor_bundle "${_sdk_dir}/lib/")
  if(NOT _vendor_import IN_LIST _sdk_links OR
      NOT "${tencent_cloud_chat_sdk_bundled_libraries}" STREQUAL _vendor_bundle OR
      NOT _vendor_bundle IN_LIST PLUGIN_BUNDLED_LIBRARIES)
    message(FATAL_ERROR "SDK native link or bundle layout changed. "
      "Re-review the Tox-only SDK policy in windows/cmake/tox_sdk.cmake.")
  endif()
  list(REMOVE_ITEM _sdk_links "${_vendor_import}")
  set_property(TARGET tencent_cloud_chat_sdk_plugin
    PROPERTY LINK_LIBRARIES "${_sdk_links}")

  set(_bundled ${PLUGIN_BUNDLED_LIBRARIES})
  list(REMOVE_ITEM _bundled "${_vendor_bundle}")
  # Replace only this vendor directory entry. Keep all other plugins, the shim
  # itself, and any unrelated files added to the directory in the future.
  file(GLOB _sdk_files CONFIGURE_DEPENDS "${_sdk_dir}/lib/*")
  foreach(_name ImSDK.dll dart_native_imsdk.dll ImSDK.lib dart_native_imsdk.lib)
    list(REMOVE_ITEM _sdk_files "${_sdk_dir}/lib/${_name}")
  endforeach()
  list(APPEND _bundled ${_sdk_files})
  set(PLUGIN_BUNDLED_LIBRARIES "${_bundled}" PARENT_SCOPE)

  # Incremental builds can retain files copied by the old whole-directory rule.
  # Evaluate the prefix at install time so --prefix and DESTDIR remain correct.
  install(CODE [[
    foreach(_name ImSDK.dll dart_native_imsdk.dll ImSDK.lib dart_native_imsdk.lib)
      file(REMOVE "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/${_name}")
    endforeach()
  ]] COMPONENT Runtime)
endfunction()

toxee_use_tim2tox_windows_sdk()
