import { MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { FlutterPluginBinding } from '@ohos/flutter_ohos';
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
      const args = call.arguments() as Record<string, Object>;
      const maskAllTexts = args['maskAllTexts'] as boolean ?? true;
      const maskAllImages = args['maskAllImages'] as boolean ?? true;
      const throttleDelayMs = args['throttleDelayMs'] as number ?? 1000;

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
      result.error('SETUP_ERROR', `Failed to setup session replay: ${e.message}`, null);
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
      result.error('PLATFORM_ERROR', `Failed to get platform version: ${e.message}`, null);
    }
  }

  /**
   * Get device information
   */
  private getDeviceInfo(result: MethodResult): void {
    try {
      const info = this.deviceInfo.getDeviceInfo();
      result.success(info);
    } catch (e) {
      this.logger.error('Failed to get device info', e);
      result.error('DEVICE_INFO_ERROR', `Failed to get device info: ${e.message}`, null);
    }
  }

  /**
   * Open URL in system browser
   */
  private openUrl(call: MethodCall, result: MethodResult): void {
    try {
      const url = call.arguments() as string;
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
      result.error('OPEN_URL_ERROR', `Failed to open URL: ${e.message}`, null);
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
      result.error('CAPTURE_ERROR', `Failed to capture screenshot: ${e.message}`, null);
    }
  }
}
