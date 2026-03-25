import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class PanScrollView extends StatefulWidget {
  const PanScrollView({
    super.key,
    required this.child,
    this.horizontal = true,
    this.vertical = true,
    this.showScrollbars = true,
    this.padding,
  });

  final Widget child;
  final bool horizontal;
  final bool vertical;
  final bool showScrollbars;
  final EdgeInsetsGeometry? padding;

  @override
  State<PanScrollView> createState() => _PanScrollViewState();
}

class _PanScrollViewState extends State<PanScrollView> {
  ScrollController? _horizontalController;
  ScrollController? _verticalController;

  @override
  void initState() {
    super.initState();
    if (widget.horizontal) {
      _horizontalController = ScrollController();
    }
    if (widget.vertical) {
      _verticalController = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant PanScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.horizontal != widget.horizontal) {
      _horizontalController?.dispose();
      _horizontalController = widget.horizontal ? ScrollController() : null;
    }
    if (oldWidget.vertical != widget.vertical) {
      _verticalController?.dispose();
      _verticalController = widget.vertical ? ScrollController() : null;
    }
  }

  @override
  void dispose() {
    _horizontalController?.dispose();
    _verticalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    Widget scrollView = ScrollConfiguration(
      behavior: const _PanScrollBehavior(),
      child: _buildScrollView(content),
    );

    if (!widget.showScrollbars) {
      return scrollView;
    }

    if (widget.vertical && widget.horizontal) {
      return Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: Scrollbar(
          controller: _horizontalController,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: scrollView,
        ),
      );
    }

    if (widget.vertical) {
      return Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: scrollView,
      );
    }

    return Scrollbar(
      controller: _horizontalController,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      thumbVisibility: true,
      child: scrollView,
    );
  }

  Widget _buildScrollView(Widget child) {
    if (widget.vertical && widget.horizontal) {
      return SingleChildScrollView(
        controller: _verticalController,
        scrollDirection: Axis.vertical,
        primary: false,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          primary: false,
          child: child,
        ),
      );
    }
    if (widget.vertical) {
      return SingleChildScrollView(
        controller: _verticalController,
        scrollDirection: Axis.vertical,
        primary: false,
        child: child,
      );
    }
    if (widget.horizontal) {
      return SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        primary: false,
        child: child,
      );
    }
    return child;
  }
}

class _PanScrollBehavior extends MaterialScrollBehavior {
  const _PanScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}
