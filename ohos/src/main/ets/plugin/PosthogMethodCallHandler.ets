import { MethodCall, MethodResult, FlutterPluginBinding } from '@ohos/flutter_ohos';
import { DeviceInfo } from './utils/DeviceInfo';
import { Logger } from './utils/Logger';
import { SessionReplayManager } from './screenshot/SessionReplayManager';

/**
 * PostHog Method Channel Call Handler
 * Handles method calls from Flutter through MethodChannel
 */
export class PosthogMethodCallHandler {
  private deviceInfo: DeviceInfo;
  private sessionReplayManager: SessionReplayManager;
  private logger: Logger = new Logger('PosthogMethodCallHandler');

  constructor(binding: FlutterPluginBinding) {
    this.deviceInfo = new DeviceInfo();
    this.sessionReplayManager = new SessionReplayManager(binding.getApplicationContext());
    this.logger.info('PosthogMethodCallHandler initialized');
  }

  /**
   * Handle method calls from Flutter
   */
  handleMethodCall(call: MethodCall, result: MethodResult): void {
    this.logger.debug(`Received method call: ${call.method}`);

    switch (call.method) {
      case 'setup':
        this.setup(call, result);
        break;
      case 'getPlatformVersion':
        this.getPlatformVersion(result);
        break;
      case 'getDeviceInfo':
        this.getDeviceInfo(result);
        break;
      case 'openUrl':
        this.openUrl(call, result);
        break;
      case 'captureScreenshot':
        this.handleCaptureScreenshot(call, result);
        break;
      case 'isSessionReplayActive':
        result.success(this.sessionReplayManager.checkIsActive());
        break;
      case 'setupSessionReplay':
        this.handleSetupSessionReplay(call, result);
        break;
      case 'screen':
        this.screen(call, result);
        break;
      case 'alias':
        this.alias(call, result);
        break;
      case 'identify':
        this.identify(call, result);
        break;
      case 'capture':
        this.capture(call, result);
        break;
      case 'flush':
        this.flush(result);
        break;
      case 'reset':
        this.reset(result);
        break;
      case 'enable':
        this.enable(result);
        break;
      case 'disable':
        this.disable(result);
        break;
      case 'debug':
        this.debug(call, result);
        break;
      default:
        this.logger.warn(`Method not implemented: ${call.method}`);
        result.notImplemented();
    }
  }

  /**
   * Setup session replay with configuration
   */
  private handleSetupSessionReplay(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const maskAllTexts = (args['maskAllTexts'] as boolean) ?? true;
      const maskAllImages = (args['maskAllImages'] as boolean) ?? true;
      const throttleDelayMs = (args['throttleDelayMs'] as number) ?? 1000;

      this.sessionReplayManager.setMaskAllTexts(maskAllTexts);
      this.sessionReplayManager.setMaskAllImages(maskAllImages);
      this.sessionReplayManager.setThrottleDelay(throttleDelayMs);

      // Activate session replay if not already active
      if (!this.sessionReplayManager.checkIsActive()) {
        this.sessionReplayManager.setActive(true);
      }

      this.logger.info('Session replay setup completed');
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to setup session replay', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('SETUP_ERROR', `Failed to setup session replay: ${errorMessage}`, null);
    }
  }

  /**
   * Get platform version
   */
  private getPlatformVersion(result: MethodResult): void {
    try {
      const version = this.deviceInfo.getOSVersion();
      result.success(version);
    } catch (e) {
      this.logger.error('Failed to get platform version', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('PLATFORM_ERROR', `Failed to get platform version: ${errorMessage}`, null);
    }
  }

  /**
   * Get device information
   */
  private getDeviceInfo(result: MethodResult): void {
    try {
      const info: ESObject = this.deviceInfo.getDeviceInfo();
      result.success(info);
    } catch (e) {
      this.logger.error('Failed to get device info', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('DEVICE_INFO_ERROR', `Failed to get device info: ${errorMessage}`, null);
    }
  }

  /**
   * Open URL in system browser
   */
  private openUrl(call: MethodCall, result: MethodResult): void {
    try {
      const url: string = call.args as string;
      if (!url) {
        result.error('INVALID_ARGUMENT', 'URL is null or empty', null);
        return;
      }

      // Use @ohos.app.ability.common.Want to open URL
      // This is a placeholder - actual implementation depends on HarmonyOS API
      this.logger.info(`Opening URL: ${url}`);
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to open URL', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('OPEN_URL_ERROR', `Failed to open URL: ${errorMessage}`, null);
    }
  }

  /**
   * Handle screenshot capture
   */
  private async handleCaptureScreenshot(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      await this.sessionReplayManager.handleScreenshotCapture(call, result);
    } catch (e) {
      this.logger.error('Failed to capture screenshot', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('CAPTURE_ERROR', `Failed to capture screenshot: ${errorMessage}`, null);
    }
  }

  /**
   * Setup PostHog with configuration
   */
  private setup(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      this.logger.info(`PostHog setup called with apiKey: ${args['apiKey']}`);

      // For HarmonyOS, we just acknowledge the setup
      // Actual analytics would be sent to server
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to setup PostHog', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('SETUP_ERROR', `Failed to setup PostHog: ${errorMessage}`, null);
    }
  }

  /**
   * Track screen view
   */
  private screen(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const screenName = args['screenName'] as string;
      const properties: ESObject | null = args['properties'] as ESObject | null;

      this.logger.info(`Screen view tracked: ${screenName}`);
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to track screen', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('SCREEN_ERROR', `Failed to track screen: ${errorMessage}`, null);
    }
  }

  /**
   * Create user alias
   */
  private alias(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const alias = args['alias'] as string;
      const distinctId = args['distinctId'] as string;

      this.logger.info(`Alias created: ${alias} -> ${distinctId}`);
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to create alias', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('ALIAS_ERROR', `Failed to create alias: ${errorMessage}`, null);
    }
  }

  /**
   * Identify user
   */
  private identify(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const userId = args['userId'] as string;
      const properties: ESObject | null = args['properties'] as ESObject | null;

      this.logger.info(`User identified: ${userId}`);
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to identify user', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('IDENTIFY_ERROR', `Failed to identify user: ${errorMessage}`, null);
    }
  }

  /**
   * Capture event
   */
  private capture(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const eventName = args['eventName'] as string;
      const properties: ESObject | null = args['properties'] as ESObject | null;

      this.logger.info(`Event captured: ${eventName}`);
      // TODO: Send event to PostHog server
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to capture event', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('CAPTURE_ERROR', `Failed to capture event: ${errorMessage}`, null);
    }
  }

  /**
   * Flush queued events
   */
  private flush(result: MethodResult): void {
    try {
      this.logger.info('Flushed events');
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to flush', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('FLUSH_ERROR', `Failed to flush: ${errorMessage}`, null);
    }
  }

  /**
   * Reset user
   */
  private reset(result: MethodResult): void {
    try {
      this.logger.info('User reset');
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to reset', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('RESET_ERROR', `Failed to reset: ${errorMessage}`, null);
    }
  }

  /**
   * Enable PostHog
   */
  private enable(result: MethodResult): void {
    try {
      this.logger.info('PostHog enabled');
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to enable', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('ENABLE_ERROR', `Failed to enable: ${errorMessage}`, null);
    }
  }

  /**
   * Disable PostHog
   */
  private disable(result: MethodResult): void {
    try {
      this.logger.info('PostHog disabled');
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to disable', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('DISABLE_ERROR', `Failed to disable: ${errorMessage}`, null);
    }
  }

  /**
   * Set debug mode
   */
  private debug(call: MethodCall, result: MethodResult): void {
    try {
      const args: ESObject = call.args as ESObject;
      const enabled = args['enabled'] as boolean;

      this.logger.info(`Debug mode: ${enabled}`);
      this.logger.setEnabled(enabled);
      result.success(null);
    } catch (e) {
      this.logger.error('Failed to set debug', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('DEBUG_ERROR', `Failed to set debug: ${errorMessage}`, null);
    }
  }
}
