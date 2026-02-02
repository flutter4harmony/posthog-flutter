import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { PosthogMethodCallHandler } from './PosthogMethodCallHandler';
import { Logger } from './utils/Logger';

/**
 * PostHog Flutter Plugin for HarmonyOS
 * Main plugin class that bridges Flutter and HarmonyOS
 */
export default class PosthogFlutterPlugin implements FlutterPlugin, MethodCallHandler {
  private static CHANNEL: string = 'posthog_flutter';
  private methodChannel: MethodChannel | null = null;
  private callHandler: PosthogMethodCallHandler | null = null;
  private logger: Logger = new Logger('PosthogFlutterPlugin');

  constructor() {
    this.logger.info('PosthogFlutterPlugin constructed');
  }

  /**
   * Get unique class name for Flutter plugin registry
   */
  getUniqueClassName(): string {
    return 'PosthogFlutterPlugin';
  }

  /**
   * Called when plugin is attached to Flutter engine
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.logger.info('PosthogFlutterPlugin attached to engine');

    // Create method channel
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), PosthogFlutterPlugin.CHANNEL);

    // Create method call handler
    this.callHandler = new PosthogMethodCallHandler(binding);

    // Set method call handler
    this.methodChannel.setMethodCallHandler(this);

    this.logger.info('Method channel initialized');
  }

  /**
   * Called when plugin is detached from Flutter engine
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.logger.info('PosthogFlutterPlugin detached from engine');

    if (this.methodChannel !== null) {
      this.methodChannel.setMethodCallHandler(null);
      this.methodChannel = null;
    }

    this.callHandler = null;
  }

  /**
   * Handle method calls from Flutter
   */
  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.logger.debug(`Received method call: ${call.method}`);

    if (this.callHandler !== null) {
      this.callHandler.handleMethodCall(call, result);
    } else {
      this.logger.warn('Call handler is null, method not implemented');
      result.notImplemented();
    }
  }

  /**
   * Get the method channel name
   */
  static getChannelName(): string {
    return PosthogFlutterPlugin.CHANNEL;
  }
}
