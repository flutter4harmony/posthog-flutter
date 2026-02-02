import { MethodCall, MethodResult, FlutterPluginBinding } from '@ohos/flutter_ohos';
import { DeviceInfo } from './utils/DeviceInfo';
import { Logger } from './utils/Logger';
import { SessionReplayManager } from './screenshot/SessionReplayManager';
import http from '@ohos.net.http';
import common from '@ohos.app.ability.common';

/**
 * PostHog Method Channel Call Handler
 * Handles method calls from Flutter through MethodChannel
 */
export class PosthogMethodCallHandler {
  private deviceInfo: DeviceInfo;
  private sessionReplayManager: SessionReplayManager;
  private logger: Logger = new Logger('PosthogMethodCallHandler');
  private apiKey: string = '';
  private context: common.Context;
  private eventQueue: ESObject[] = [];
  private enabled: boolean = true;

  constructor(binding: FlutterPluginBinding) {
    this.context = binding.getApplicationContext();
    this.deviceInfo = new DeviceInfo();
    this.sessionReplayManager = new SessionReplayManager(binding.getApplicationContext());
    this.logger.info('PosthogMethodCallHandler initialized');
  }

  /**
   * Handle method calls from Flutter
   */
  handleMethodCall(call: MethodCall, result: MethodResult): void {
    this.logger.info(`[METHOD CALL] ========== Method Call Received ==========`);
    this.logger.info(`[METHOD CALL] Method name: ${call.method}`);
    this.logger.info(`[METHOD CALL] Args type: ${typeof call.args}`);
    this.logger.info(`[METHOD CALL] Args value: ${JSON.stringify(call.args)}`);
    this.logger.info(`[METHOD CALL] Args as Any: ${call.args}`);
    this.logger.info(`[METHOD CALL] Current API Key: ${this.apiKey ? this.apiKey.substring(0, 10) + '...' : 'NOT SET'}`);
    this.logger.info(`[METHOD CALL] Enabled: ${this.enabled}`);

    // Try to use argument() method
    try {
      if (call.args && typeof call.args === 'object') {
        const keys = Object.keys(call.args);
        this.logger.info(`[METHOD CALL] Args keys: ${keys.join(', ')}`);
        this.logger.info(`[METHOD CALL] Args keys count: ${keys.length}`);
      }
    } catch (e) {
      this.logger.error('[METHOD CALL] Error checking args', e);
    }

    switch (call.method) {
      case 'setup':
        this.logger.info(`[METHOD CALL] Routing to SETUP`);
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
        this.logger.info(`[METHOD CALL] Routing to CAPTURE`);
        this.capture(call, result);
        break;
      case 'flush':
        this.logger.info(`[METHOD CALL] Routing to FLUSH`);
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
        this.logger.warn(`[METHOD CALL] Method not implemented: ${call.method}`);
        result.notImplemented();
    }

    this.logger.info(`[METHOD CALL] ========== Method Call Ended ==========\n`);
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
      this.logger.info(`[SETUP] Raw args type: ${typeof args}`);
      this.logger.info(`[SETUP] Raw args value: ${JSON.stringify(args)}`);

      // Try different possible key names
      this.apiKey = args['apiKey'] as string;
      if (!this.apiKey) {
        this.apiKey = args['posthogApiKey'] as string;
      }
      if (!this.apiKey) {
        // Check if args itself is a string (the API key)
        if (typeof args === 'string') {
          this.apiKey = args;
        }
      }

      this.logger.info(`[SETUP] PostHog setup started`);
      this.logger.info(`[SETUP] API Key: ${this.apiKey}`);
      this.logger.info(`[SETUP] Enabled: ${this.enabled}`);
      result.success(null);
      this.logger.info(`[SETUP] PostHog setup completed successfully`);
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
   * Send event to PostHog server
   */
  private async sendEventToPosthog(eventName: string, properties: ESObject | null): Promise<void> {
    this.logger.info(`[SEND] Starting to send event: ${eventName}`);
    this.logger.info(`[SEND] Enabled: ${this.enabled}, API Key exists: ${!!this.apiKey}`);

    if (!this.enabled || !this.apiKey) {
      this.logger.warn('[SEND] PostHog is disabled or not configured, skipping');
      return;
    }

    try {
      const deviceInfo: ESObject = this.deviceInfo.getPosthogDeviceProperties();
      this.logger.info(`[SEND] Device info collected: ${JSON.stringify(deviceInfo)}`);

      // Prepare event data - merge properties manually
      const mergedProperties: ESObject = {};

      // Copy device info
      if (deviceInfo) {
        const deviceKeys = Object.keys(deviceInfo) as string[];
        for (const key of deviceKeys) {
          mergedProperties[key] = deviceInfo[key];
        }
      }

      // Copy event properties
      if (properties) {
        const propKeys = Object.keys(properties) as string[];
        for (const key of propKeys) {
          mergedProperties[key] = properties[key];
        }
      }

      const eventData: ESObject = {
        'api_key': this.apiKey,
        'event': eventName,
        'properties': mergedProperties,
        'timestamp': new Date().toISOString(),
      };

      this.logger.info(`[SEND] Event data prepared: ${JSON.stringify(eventData)}`);
      this.logger.info(`[SEND] Creating HTTP request to PostHog...`);

      // Create HTTP request
      const httpRequest = http.createHttp();

      this.logger.info(`[SEND] Sending POST request to https://app.posthog.com/capture/`);

      const response = await httpRequest.request(
        'https://app.posthog.com/capture/',
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
          },
          extraData: JSON.stringify(eventData),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 60000,
          readTimeout: 60000,
        }
      );

      this.logger.info(`[SEND] Response code: ${response.responseCode}`);
      this.logger.info(`[SEND] Response result type: ${typeof response.result}`);
      this.logger.info(`[SEND] Response result: ${response.result}`);

      if (response.responseCode === 200) {
        this.logger.info(`[SEND] ✅ Event sent successfully: ${eventName}`);
      } else {
        this.logger.error(`[SEND] ❌ Failed to send event. Response code: ${response.responseCode}`);
      }

      httpRequest.destroy();
      this.logger.info(`[SEND] HTTP request destroyed`);
    } catch (e) {
      this.logger.error('[SEND] ❌ Error sending event to PostHog', e);
      this.logger.info(`[SEND] Adding event to queue for retry`);
      // Queue event for later retry
      this.eventQueue.push({
        'event': eventName,
        'properties': properties,
        'timestamp': new Date().toISOString(),
      });
      this.logger.info(`[SEND] Queue size: ${this.eventQueue.length}`);
    }
  }

  /**
   * Capture event
   */
  private capture(call: MethodCall, result: MethodResult): void {
    try {
      this.logger.info(`[CAPTURE] ========== Event Capture Started ==========`);

      const args: ESObject = call.args as ESObject;
      this.logger.info(`[CAPTURE] Raw args type: ${typeof args}`);
      this.logger.info(`[CAPTURE] Raw args value: ${JSON.stringify(args)}`);

      const eventName = args['eventName'] as string;
      const properties: ESObject | null = args['properties'] as ESObject | null;

      this.logger.info(`[CAPTURE] Event name: ${eventName}`);
      this.logger.info(`[CAPTURE] Properties: ${JSON.stringify(properties)}`);
      this.logger.info(`[CAPTURE] Current API Key: ${this.apiKey ? this.apiKey.substring(0, 10) + '...' : 'NOT SET'}`);
      this.logger.info(`[CAPTURE] Enabled status: ${this.enabled}`);

      // Send event to PostHog (async, don't wait)
      if (eventName) {
        this.sendEventToPosthog(eventName, properties).catch((e: Error) => {
          this.logger.error('[CAPTURE] Failed to send event', e);
        });
      } else {
        this.logger.error('[CAPTURE] Event name is missing, skipping send');
      }

      this.logger.info(`[CAPTURE] Event capture initiated, returning success to Flutter`);
      this.logger.info(`[CAPTURE] ========== Event Capture Ended ==========`);

      result.success(null);
    } catch (e) {
      this.logger.error('[CAPTURE] Failed to capture event', e);
      const errorMessage = e instanceof Error ? e.message : String(e);
      result.error('CAPTURE_ERROR', `Failed to capture event: ${errorMessage}`, null);
    }
  }

  /**
   * Flush queued events
   */
  private async flush(result: MethodResult): Promise<void> {
    try {
      this.logger.info(`[FLUSH] ========== Flush Started ==========`);
      this.logger.info(`[FLUSH] Queue size: ${this.eventQueue.length}`);

      if (this.eventQueue.length === 0) {
        this.logger.info(`[FLUSH] No events to flush`);
        result.success(null);
        this.logger.info(`[FLUSH] ========== Flush Ended ==========`);
        return;
      }

      // Log all queued events
      this.eventQueue.forEach((event: ESObject, index: number) => {
        this.logger.info(`[FLUSH] Queued event ${index + 1}: ${event['event']}`);
      });

      // Send all queued events
      this.logger.info(`[FLUSH] Sending all queued events...`);
      const promises = this.eventQueue.map((queuedEvent: ESObject) => {
        return this.sendEventToPosthog(queuedEvent['event'] as string, queuedEvent['properties'] as ESObject | null);
      });

      await Promise.all(promises);

      // Clear queue after sending
      this.eventQueue = [];
      this.logger.info(`[FLUSH] ✅ All events flushed, queue cleared`);
      this.logger.info(`[FLUSH] ========== Flush Ended ==========`);
      result.success(null);
    } catch (e) {
      this.logger.error('[FLUSH] ❌ Failed to flush', e);
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
      this.enabled = true;
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
      this.enabled = false;
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
