import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/zen_master/model/view_model.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'package:provider/provider.dart';

/// View for Zen Master: helps you stay still for meditation
///
/// The view displays a play button/countdown timer/timer in the center of the screen,
/// and a dial/stop button in the bottom of the screen.
///
class ZenMasterView extends StatefulWidget {
  final Wearable wearable;
  final SensorConfigurationProvider sensorConfigurationProvider;

  const ZenMasterView({
    super.key,
    required this.wearable,
    required this.sensorConfigurationProvider,
  });

  @override
  State<ZenMasterView> createState() => _ZenMasterViewState();
}

class _ZenMasterViewState extends State<ZenMasterView> {
  static const double _pickerHeight = 200;
  static const double _centerDisplaySize = 180;
  static const Color _green = Colors.green;

  late final ZenMasterViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ZenMasterViewModel(
      wearable: widget.wearable,
      sensorConfigurationProvider: widget.sensorConfigurationProvider,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<ZenMasterViewModel>(
        builder: (context, model, _) {
          return PlatformScaffold(
            appBar: PlatformAppBar(
              title: PlatformText("Zen Master"),
              backgroundColor: Theme.of(context).colorScheme.surface,
              material: (_, __) => MaterialAppBarData(
                elevation: 0,
                scrolledUnderElevation: 0,
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double height = constraints.maxHeight;
                  // Arrange vertical space for layout
                  final double slotHeight = height / 6;
                  final double playCenterY = slotHeight * 2.5;
                  final double dialCenterY = slotHeight * 4.5;
                  final String statusLabel = model.statusLabelText();

                  // Clamp positions so fixed-size widgets don't overflow
                  final double playTop = math.max(
                    0,
                    math.min(
                      height - _centerDisplaySize,
                      playCenterY - _centerDisplaySize / 2,
                    ),
                  );
                  final double dialTop = math.max(
                    0,
                    math.min(
                      height - _pickerHeight,
                      dialCenterY - _pickerHeight / 2,
                    ),
                  );
                  final double statusTop = math.max(0, playTop - 36);

                  return Stack(
                    children: [
                      if (statusLabel.isNotEmpty)
                        Positioned(
                          top: statusTop,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: PlatformText(
                              statusLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      Positioned(
                        top: playTop,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: animatedCenterDisplay(context, model),
                        ),
                      ),
                      Positioned(
                        top: dialTop,
                        left: 0,
                        right: 0,
                        child: bottomArea(context, model),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Animates the center display (play button, countdown timer, timer) between the current phase and the next phase.
  Widget animatedCenterDisplay(BuildContext context, ZenMasterViewModel model) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.95, end: 1.0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: SizedBox(
        key: ValueKey(model.phase),
        width: _centerDisplaySize,
        height: _centerDisplaySize,
        child: Center(
          child: centerDisplay(context, model),
        ),
      ),
    );
  }

  /// Displays the center display (play button, countdown timer, timer) based on the current phase.
  Widget centerDisplay(BuildContext context, ZenMasterViewModel model) {
    switch (model.phase) {
      case ZenMasterPhase.idle:
        return playButton(context, model);
      case ZenMasterPhase.countdown:
        return ringDisplay(
          context,
          model,
          label: model.countdownRemaining.toString(),
        );
      case ZenMasterPhase.running:
        return ringDisplay(
          context,
          model,
          label: formatDuration(model.remainingDuration),
        );
    }
  }

  /// Displays the play button in the center of the screen.
  Widget playButton(BuildContext context, ZenMasterViewModel model) {
    return GestureDetector(
      onTap: model.startCountdown,
      child: Container(
        width: _centerDisplaySize,
        height: _centerDisplaySize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _green,
        ),
        child: Icon(
          Icons.play_arrow,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 88,
        ),
      ),
    );
  }

  /// Displays the ring display (for countdown timer and timer)
  Widget ringDisplay(
    BuildContext context,
    ZenMasterViewModel model, {
    required String label,
  }) {
    // Ring color reflects deadzone status (green = still, red = moving).
    final Color ringColor = model.isInDeadzone ? _green : Colors.red;
    return Container(
      width: _centerDisplaySize,
      height: _centerDisplaySize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ringColor,
          width: 8,
        ),
      ),
      child: Center(
        child: PlatformText(
          label,
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
    );
  }

  /// Ensures consistent size of bottom area containing dial or stop button
  Widget bottomArea(BuildContext context, ZenMasterViewModel model) {
    return Center(
      child: SizedBox(
        height: _pickerHeight,
        child: Center(
          child: dialOrStopButtonContent(context, model),
        ),
      ),
    );
  }

  /// Dial in idle, stop button in countdown/running, animated between them.
  Widget dialOrStopButtonContent(
    BuildContext context,
    ZenMasterViewModel model,
  ) {
    final Widget content = model.phase == ZenMasterPhase.idle
        ? durationPicker(model)
        : PlatformElevatedButton(
            onPressed: model.stopSession,
            child: PlatformText("Stop"),
            material: (_, __) => MaterialElevatedButtonData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
            cupertino: (_, __) => CupertinoElevatedButtonData(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(model.phase == ZenMasterPhase.idle),
        child: content,
      ),
    );
  }

  /// Pick duration in dial - chose CupertinoTimerPicker because it works better for use case and design.
  Widget durationPicker(ZenMasterViewModel model) {
    return SizedBox(
      height: _pickerHeight,
      child: CupertinoTimerPicker(
        mode: CupertinoTimerPickerMode.ms,
        initialTimerDuration: model.selectedDuration,
        onTimerDurationChanged: model.updateSelectedDuration,
      ),
    );
  }

  /// Format duration for display in timer display.
  String formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds.clamp(0, 359999);
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }
}
