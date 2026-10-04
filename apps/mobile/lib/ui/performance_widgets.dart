import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'accessibility.dart';
import 'motion.dart';

/// Uses the viewport's builder; avoid shrinkWrap inside another scrolling list.
class VirtualizedListView<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context)? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final Key Function(T item)? itemKey;

  const VirtualizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding,
    this.controller,
    this.shrinkWrap = false,
    this.physics,
    this.itemKey,
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    controller: controller,
    padding: padding,
    shrinkWrap: shrinkWrap,
    physics: physics,
    itemCount: items.length,
    itemBuilder: (context, index) => _listItem(
      context,
      items[index],
      index,
      items.length,
      itemBuilder,
      itemKey,
    ),
    separatorBuilder: (context, _) =>
        separatorBuilder?.call(context) ?? const SizedBox.shrink(),
  );
}

/// A lazy sliver for pages that already own a CustomScrollView.
class VirtualizedSliverList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context)? separatorBuilder;
  final Key Function(T item)? itemKey;

  const VirtualizedSliverList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.separatorBuilder,
    this.itemKey,
  });

  @override
  Widget build(BuildContext context) {
    final separated = separatorBuilder != null;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, position) {
          if (separated && position.isOdd) return separatorBuilder!(context);
          final index = separated ? position ~/ 2 : position;
          return _listItem(
            context,
            items[index],
            index,
            items.length,
            itemBuilder,
            itemKey,
          );
        },
        childCount: items.isEmpty
            ? 0
            : (separated ? items.length * 2 - 1 : items.length),
        semanticIndexCallback: (_, index) =>
            separated ? (index.isEven ? index ~/ 2 : null) : index,
      ),
    );
  }
}

Widget _listItem<T>(
  BuildContext context,
  T item,
  int index,
  int total,
  Widget Function(BuildContext, T, int) builder,
  Key Function(T)? key,
) => SemanticListItem(
  key: key?.call(item),
  index: index,
  total: total,
  label: '',
  child: builder(context, item, index),
);

/// The caller owns items and paging; returned items are never silently appended.
/// Failed requests wait for explicit retry. Changing pagingKey retires old work.
class LazyLoadList<T> extends StatefulWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Future<List<T>> Function() onLoadMore;
  final bool hasMore;
  final Widget? loadingWidget, endWidget;
  final Widget Function(BuildContext)? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final bool loadAtStart, reverse, autoLoad;
  final double loadThreshold;
  final Object? pagingKey;
  final Key Function(T item)? itemKey;
  final void Function(Object error)? onLoadError;
  final Widget Function(BuildContext, Object, VoidCallback)? errorBuilder;

  const LazyLoadList({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.hasMore,
    this.loadingWidget,
    this.endWidget,
    this.separatorBuilder,
    this.padding,
    this.controller,
    this.loadAtStart = false,
    this.reverse = false,
    this.autoLoad = true,
    this.loadThreshold = 200,
    this.pagingKey,
    this.itemKey,
    this.onLoadError,
    this.errorBuilder,
  });

  @override
  State<LazyLoadList<T>> createState() => _LazyLoadListState<T>();
}

class _LazyLoadListState<T> extends State<LazyLoadList<T>> {
  late ScrollController _controller;
  late bool _ownsController;
  bool _loading = false;
  Object? _error;
  int _request = 0;
  int? _lastAutoCount;

  @override
  void initState() {
    super.initState();
    _attachController();
    _scheduleCheck();
  }

  void _attachController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_onScroll);
  }

  void _detachController() {
    _controller.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
  }

  @override
  void didUpdateWidget(covariant LazyLoadList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController();
    }
    if (oldWidget.pagingKey != widget.pagingKey) {
      _request++;
      _loading = false;
      _error = null;
      _lastAutoCount = null;
    }
    if (!oldWidget.hasMore && widget.hasMore) _lastAutoCount = null;
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.hasMore != widget.hasMore ||
        oldWidget.autoLoad != widget.autoLoad ||
        oldWidget.pagingKey != widget.pagingKey ||
        oldWidget.controller != widget.controller) {
      _scheduleCheck();
    }
  }

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _onScroll() {
    if (!widget.autoLoad ||
        !_controller.hasClients ||
        _loading ||
        _error != null ||
        !widget.hasMore ||
        _lastAutoCount == widget.items.length) {
      return;
    }
    final position = _controller.position;
    final distance = widget.loadAtStart
        ? position.extentBefore
        : position.extentAfter;
    if (distance <= widget.loadThreshold) {
      _lastAutoCount = widget.items.length;
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !widget.hasMore) return;
    final request = ++_request;
    final previousExtent = _controller.hasClients
        ? _controller.position.maxScrollExtent
        : null;
    final previousOffset = _controller.hasClients ? _controller.offset : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onLoadMore();
      if (!mounted || request != _request) return;
      if (widget.loadAtStart &&
          !widget.reverse &&
          previousExtent != null &&
          previousOffset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || request != _request || !_controller.hasClients) {
            return;
          }
          final position = _controller.position;
          final delta = position.maxScrollExtent - previousExtent;
          _controller.jumpTo(
            (previousOffset + delta).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
          );
        });
      }
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() => _error = error);
      widget.onLoadError?.call(error);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Widget _paging(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!, () => _loadMore()) ??
          ErrorState(message: '加载失败，请重试', onRetry: () => _loadMore());
    }
    if (_loading) {
      return widget.loadingWidget ??
          const SizedBox(height: 64, child: Center(child: LoadingDots()));
    }
    if (widget.hasMore) {
      final colors = Theme.of(context).colorScheme;
      return SizedBox(
        height: 64,
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: colors.surfaceContainerHighest.withValues(
                alpha: .6,
              ),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant),
              ),
            ),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text(widget.loadAtStart ? '载入更早的记录' : '载入更多'),
          ),
        ),
      );
    }
    return widget.endWidget ?? const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: _controller,
    reverse: widget.reverse,
    padding: widget.padding,
    itemCount: widget.items.length + 1,
    itemBuilder: (context, index) {
      if (index == (widget.loadAtStart ? 0 : widget.items.length)) {
        return _paging(context);
      }
      final itemIndex = widget.loadAtStart ? index - 1 : index;
      final row = _listItem(
        context,
        widget.items[itemIndex],
        itemIndex,
        widget.items.length,
        widget.itemBuilder,
        widget.itemKey,
      );
      return widget.separatorBuilder == null ||
              itemIndex == widget.items.length - 1
          ? row
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [row, widget.separatorBuilder!(context)],
            );
    },
  );

  @override
  void dispose() {
    _request++;
    _detachController();
    super.dispose();
  }
}

/// Private sources never use a URL cache key shared between account owners.
class OwnerScopedMemoryImage extends MemoryImage {
  final Object ownerGeneration;
  const OwnerScopedMemoryImage(super.bytes, {required this.ownerGeneration});
  @override
  bool operator ==(Object other) =>
      other is OwnerScopedMemoryImage &&
      other.ownerGeneration == ownerGeneration &&
      identical(other.bytes, bytes);
  @override
  int get hashCode => Object.hash(ownerGeneration, identityHashCode(bytes));
}

class OwnerScopedFileImage extends FileImage {
  final Object ownerGeneration;
  const OwnerScopedFileImage(super.file, {required this.ownerGeneration});
  @override
  bool operator ==(Object other) =>
      other is OwnerScopedFileImage &&
      other.ownerGeneration == ownerGeneration &&
      other.file.path == file.path;
  @override
  int get hashCode => Object.hash(ownerGeneration, file.path);
}

/// Public network images, or explicitly owner-scoped authenticated bytes/files.
class OptimizedImage extends StatefulWidget {
  final String? imageUrl;
  final Uint8List? bytes;
  final File? file;
  final Object? ownerGeneration;
  final double? width, height;
  final BoxFit fit;
  final Widget? placeholder, errorWidget;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final int maxDecodeWidth;

  const OptimizedImage({
    super.key,
    required String this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.semanticLabel,
    this.maxDecodeWidth = 1800,
  }) : bytes = null,
       file = null,
       ownerGeneration = null;

  const OptimizedImage.memory({
    super.key,
    required Uint8List this.bytes,
    required Object this.ownerGeneration,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.semanticLabel,
    this.maxDecodeWidth = 1800,
  }) : imageUrl = null,
       file = null;

  const OptimizedImage.file({
    super.key,
    required File this.file,
    required Object this.ownerGeneration,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.semanticLabel,
    this.maxDecodeWidth = 1800,
  }) : imageUrl = null,
       bytes = null;

  @override
  State<OptimizedImage> createState() => _OptimizedImageState();
}

class _OptimizedImageState extends State<OptimizedImage> {
  ImageProvider? _privateProvider;
  final Set<ImageProvider> _decodedProviders = {};

  void _evictPrivate() {
    for (final provider in _decodedProviders) {
      unawaited(provider.evict());
    }
    _decodedProviders.clear();
    _privateProvider = null;
  }

  @override
  void didUpdateWidget(covariant OptimizedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerGeneration != widget.ownerGeneration ||
        !identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.file?.path != widget.file?.path) {
      _evictPrivate();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final targetWidth =
          widget.width ?? (bounds.hasBoundedWidth ? bounds.maxWidth : 600);
      final decodeWidth = (targetWidth * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(1, widget.maxDecodeWidth.clamp(1, 4096))
          .toInt();
      ImageProvider provider;
      if (widget.bytes != null) {
        provider = _privateProvider ??= OwnerScopedMemoryImage(
          widget.bytes!,
          ownerGeneration: widget.ownerGeneration!,
        );
      } else if (widget.file != null) {
        provider = _privateProvider ??= OwnerScopedFileImage(
          widget.file!,
          ownerGeneration: widget.ownerGeneration!,
        );
      } else {
        provider = NetworkImage(widget.imageUrl!);
      }
      provider = ResizeImage.resizeIfNeeded(decodeWidth, null, provider);
      if (widget.ownerGeneration != null) _decodedProviders.add(provider);
      final image = Image(
        key: ValueKey(widget.ownerGeneration),
        image: provider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: widget.semanticLabel,
        frameBuilder: (context, child, frame, synchronous) => frame == null
            ? (widget.placeholder ??
                  SkeletonLoader(
                    width: targetWidth,
                    height: widget.height ?? 180,
                  ))
            : synchronous
            ? child
            : AnimatedOpacity(
                opacity: 1,
                duration: AppMotion.change(context),
                child: child,
              ),
        errorBuilder: (_, _, _) =>
            widget.errorWidget ?? const ErrorState(message: '图片暂时无法显示'),
      );
      return widget.borderRadius == null
          ? image
          : ClipRRect(borderRadius: widget.borderRadius!, child: image);
    },
  );

  @override
  void dispose() {
    _evictPrivate();
    super.dispose();
  }
}

/// Runs immediately and prevents duplicate submission until its Future finishes.
/// delay remains source compatible; it no longer delays valid user actions.
/// Navigation can opt out with guardAsync=false while keeping error reporting.
class DebouncedButton extends StatefulWidget {
  final FutureOr<void> Function()? onPressed;
  final Widget child;
  final Duration delay;
  final ButtonStyle? style;
  final Widget Function(BuildContext, VoidCallback?, bool)? builder;
  final void Function(Object, StackTrace)? onError;
  final bool guardAsync;
  const DebouncedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
    this.style,
    this.builder,
    this.onError,
    this.guardAsync = true,
  });
  @override
  State<DebouncedButton> createState() => _DebouncedButtonState();
}

class _DebouncedButtonState extends State<DebouncedButton> {
  bool _processing = false;
  Future<void> _press() async {
    final guard = widget.guardAsync;
    if ((guard && _processing) || widget.onPressed == null) return;
    if (guard) setState(() => _processing = true);
    try {
      await widget.onPressed!();
    } catch (error, stack) {
      if (widget.onError != null) {
        widget.onError!(error, stack);
      } else {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'SemesterOS controls',
          ),
        );
      }
    } finally {
      if (guard && mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final processing = widget.guardAsync && _processing;
    final callback = processing || widget.onPressed == null
        ? null
        : () => _press();
    return widget.builder?.call(context, callback, processing) ??
        FilledButton(
          onPressed: callback,
          style: widget.style,
          child: widget.child,
        );
  }
}

/// Bounded LRU values with real expiry and an explicit account/data owner.
class MemoryCache<K, V> {
  final LinkedHashMap<K, _CacheEntry<V>> _cache = LinkedHashMap();
  final int maxSize;
  final Duration expiration;
  final DateTime Function() clock;
  Object? _owner;
  MemoryCache({
    this.maxSize = 100,
    this.expiration = const Duration(minutes: 5),
    DateTime Function()? clock,
    Object? ownerGeneration,
  }) : assert(maxSize > 0),
       clock = clock ?? DateTime.now,
       _owner = ownerGeneration;
  void setOwner(Object? generation) {
    if (_owner != generation) {
      clear();
      _owner = generation;
    }
  }

  void _purge() =>
      _cache.removeWhere((_, entry) => !clock().isBefore(entry.expires));
  V? get(K key) {
    _purge();
    final entry = _cache.remove(key);
    if (entry == null) return null;
    _cache[key] = entry;
    return entry.value;
  }

  void set(K key, V value, {Duration? ttl}) {
    _purge();
    _cache.remove(key);
    if (maxSize <= 0) return;
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CacheEntry(value, clock().add(ttl ?? expiration));
  }

  void remove(K key) => _cache.remove(key);
  void clear() => _cache.clear();
  int get size {
    _purge();
    return _cache.length;
  }
}

class _CacheEntry<V> {
  final V value;
  final DateTime expires;
  _CacheEntry(this.value, this.expires);
}

/// Local build reuse only: inherited changes and expiry invalidate it.
/// With an explicit invalidationKey the caller must fingerprint every input;
/// without one, every parent update invalidates captured data.
class BuildCache extends StatefulWidget {
  final String cacheKey;
  final Widget Function(BuildContext context) builder;
  final Duration cacheDuration;
  final Object? invalidationKey, ownerGeneration;
  const BuildCache({
    super.key,
    required this.cacheKey,
    required this.builder,
    this.cacheDuration = const Duration(seconds: 30),
    this.invalidationKey,
    this.ownerGeneration,
  });
  @override
  State<BuildCache> createState() => _BuildCacheState();
}

class _BuildCacheState extends State<BuildCache> with WidgetsBindingObserver {
  Widget? _cached;
  Timer? _expiry;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void _invalidate() {
    _expiry?.cancel();
    _cached = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _invalidate();
  }

  @override
  void didUpdateWidget(covariant BuildCache oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invalidationKey == null ||
        oldWidget.invalidationKey != widget.invalidationKey ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.ownerGeneration != widget.ownerGeneration ||
        oldWidget.cacheDuration != widget.cacheDuration) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _expiry?.cancel();
    if (_foreground && mounted) setState(_invalidate);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cacheDuration <= Duration.zero) return widget.builder(context);
    if (_cached == null) {
      _cached = widget.builder(context);
      if (widget.cacheDuration > Duration.zero &&
          _foreground &&
          TickerMode.valuesOf(context).enabled) {
        _expiry = Timer(widget.cacheDuration, () {
          if (mounted) setState(_invalidate);
        });
      }
    }
    return _cached!;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiry?.cancel();
    super.dispose();
  }
}
