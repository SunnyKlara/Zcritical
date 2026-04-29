/// 统一结果类型 — 替代 bool 返回值和 Map<String, dynamic> 响应
///
/// 用法:
/// ```dart
/// final result = await controller.setFanSpeed(50);
/// result.when(
///   success: (data) => print('速度已设置: $data'),
///   failure: (error) => showError(error),
/// );
/// ```
sealed class Result<T> {
  const Result();

  /// 创建成功结果
  const factory Result.success(T data) = Success<T>;

  /// 创建失败结果
  const factory Result.failure(String message, {AppError? error}) = Failure<T>;

  /// 模式匹配
  R when<R>({
    required R Function(T data) success,
    required R Function(String message, AppError? error) failure,
  }) {
    return switch (this) {
      Success<T>(data: final d) => success(d),
      Failure<T>(message: final m, error: final e) => failure(m, e),
    };
  }

  /// 是否成功
  bool get isSuccess => this is Success<T>;

  /// 是否失败
  bool get isFailure => this is Failure<T>;

  /// 获取数据（失败时返回 null）
  T? get dataOrNull => switch (this) {
    Success<T>(data: final d) => d,
    Failure<T>() => null,
  };
}

/// 成功结果
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);

  @override
  String toString() => 'Success($data)';
}

/// 失败结果
class Failure<T> extends Result<T> {
  final String message;
  final AppError? error;
  const Failure(this.message, {this.error});

  @override
  String toString() => 'Failure($message${error != null ? ', $error' : ''})';
}

/// 应用错误类型
enum AppErrorType {
  /// BLE 未连接
  notConnected,

  /// BLE 发送失败
  sendFailed,

  /// 响应超时
  timeout,

  /// 参数无效
  invalidParam,

  /// 设备错误（ESP32 返回的错误码）
  deviceError,

  /// 未知错误
  unknown,
}

/// 应用错误
class AppError {
  final AppErrorType type;
  final String? detail;
  final Object? originalError;

  const AppError({
    required this.type,
    this.detail,
    this.originalError,
  });

  @override
  String toString() => 'AppError($type${detail != null ? ': $detail' : ''})';
}
