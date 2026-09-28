import 'package:flutter/material.dart';

/// Shared navigator key so services (like [GeofenceMonitor]) can push
/// screens on top of whatever the user is currently looking at.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
