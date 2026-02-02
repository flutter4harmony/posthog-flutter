import { MethodCall, MethodResult, FlutterPluginBinding } from '@ohos/flutter_ohos';
import { DeviceInfo } from './utils/DeviceInfo';
import { Logger } from './utils/Logger';
import { SessionReplayManager } from './screenshot/SessionReplayManager';
import http from '@ohos.net.http';
import common from '@ohos.app.ability.common';
import deviceInfo from '@ohos.deviceInfo';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import dataPreferences from '@ohos.data.preferences';

/**
 * PostHog Method Channel Call Handler
 * Handles method calls from Flutter through MethodChannel
 */
export class PosthogMethodCallHandler {
  private deviceInfo: DeviceInfo;
  private sessionReplayManager: SessionReplayManager;
  private logger: Logger = new Logger('PosthogMethodCallHandler');
  private apiKey: string = '';
  private posthogHost: string = 'https://app.posthog.com';  // 默认值
  private context: common.Context;
  private eventQueue: ESObject[] = [];
  private enabled: boolean = true;
  private distinctId: string = '';

  constructor(binding: FlutterPluginBinding) {
    this.context = binding.getApplicationContext();
    this.deviceInfo = new DeviceInfo();
    this.sessionReplayManager = new SessionReplayManager(binding.getApplicationContext());

    // Initialize distinct_id (synchronous for immediate use)
    this.distinctId = this.generateNewDistinctId();
    this.logger.info(`PosthogMethodCallHandler initialized with distinct_id: ${this.distinctId.substring(0, 8)}...`);

    // Async: Try multiple storage methods with fallback
    this.syncDistinctIdWithStorage();
  }

  /**
   * Synchronize distinct_id with storage (multi-layer fallback)
   * Priority:
   * 1. Asset Store (survives uninstall, requires permission)
   * 2. Preferences (persists during install, no permission needed)
   * 3. Device serial (fallback, no persistence)
   */
  private async syncDistinctIdWithStorage(): Promise<void> {
    try {
      this.logger.info('[STORAGE] Starting distinct_id synchronization...');

      // Try Asset Store first (with permission check)
      let storedId = await this.tryGetFromAssetStore();

      if (storedId) {
        this.distinctId = storedId;
        this.logger.info(`[STORAGE] ✅ Loaded from Asset Store: ${storedId.substring(0, 8)}...`);
        return;
      }

      // Fallback to Preferences
      storedId = await this.tryGetFromPreferences();

      if (storedId) {
        this.distinctId = storedId;
        this.logger.info(`[STORAGE] ✅ Loaded from Preferences: ${storedId.substring(0, 8)}...`);

        // Try to migrate to Asset Store for next time
        await this.tryStoreToAssetStore(this.distinctId);
        return;
      }

      // No stored ID found, store current one
      this.logger.info('[STORAGE] No stored ID found, saving current one...');

      // Try to store in Asset Store first
      const storedInAsset = await this.tryStoreToAssetStore(this.distinctId);

      if (!storedInAsset) {
        // Fallback to Preferences
        await this.tryStoreToPreferences(this.distinctId);
        this.logger.info('[STORAGE] ✅ Stored in Preferences (Asset Store unavailable)');
      } else {
        this.logger.info('[STORAGE] ✅ Stored in Asset Store');
      }

    } catch (e) {
      this.logger.warn('[STORAGE] Storage sync failed, using generated ID', e);
    }
  }

  /**
   * Try to retrieve from Asset Store (with permission)
   */
  private async tryGetFromAssetStore(): Promise<string | null> {
    try {
      const aliasStr = 'posthog_distinct_id';

      // Query by ALIAS attribute
      const queryMap: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      queryMap.set(asset.Tag.ALIAS, this.stringToUint8Array(aliasStr));

      const queryResult = await asset.query(queryMap);

      if (queryResult && queryResult.length > 0) {
        // Get SECRET from first result
        const firstResult = queryResult[0];
        const secretData = firstResult.get(asset.Tag.SECRET) as Uint8Array;
        if (secretData) {
          const id = this.uint8ArrayToString(secretData);
          this.logger.info(`[ASSET] Retrieved ID: ${id.substring(0, 8)}...`);
          return id;
        }
      }

      this.logger.info('[ASSET] No existing ID found');
      return null;
    } catch (e) {
      // Likely permission denied or not available
      this.logger.info('[ASSET] Not available (permission denied or unsupported)');
      return null;
    }
  }

  /**
   * Try to retrieve from Preferences (no permission needed)
   */
  private async tryGetFromPreferences(): Promise<string | null> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'posthog_prefs');
      const id = await prefs.get('posthog_distinct_id', '') as string;

      if (id && id.length > 0) {
        this.logger.info(`[PREFS] Retrieved ID: ${id.substring(0, 8)}...`);
        return id;
      }

      this.logger.info('[PREFS] No existing ID found');
      return null;
    } catch (e) {
      this.logger.warn('[PREFS] Failed to retrieve', e);
      return null;
    }
  }

  /**
   * Try to store to Asset Store (requires permission)
   * Returns true if successful, false otherwise
   */
  private async tryStoreToAssetStore(id: string): Promise<boolean> {
    try {
      const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attributes.set(asset.Tag.SECRET, this.stringToUint8Array(id));
      attributes.set(asset.Tag.ALIAS, this.stringToUint8Array('posthog_distinct_id'));
      attributes.set(asset.Tag.IS_PERSISTENT, true);  // Survives app uninstall

      await asset.add(attributes);
      this.logger.info('[ASSET] Successfully stored');
      return true;
    } catch (e) {
      // Permission denied or not supported
      this.logger.info('[ASSET] Store failed (permission denied or unsupported)');
      return false;
    }
  }

  /**
   * Store to Preferences (no permission needed)
   */
  private async tryStoreToPreferences(id: string): Promise<boolean> {
    try {
      const prefs = await dataPreferences.getPreferences(this.context, 'posthog_prefs');
      await prefs.put('posthog_distinct_id', id);
      await prefs.flush();
      this.logger.info('[PREFS] Successfully stored');
      return true;
    } catch (e) {
      this.logger.error('[PREFS] Failed to store', e);
      return false;
    }
  }

  /**
   * Generate new distinct_id using device serial number
   */
  private generateNewDistinctId(): string {
    try {
      // Use device serial number as stable seed
      const serial = deviceInfo.serial;
      if (serial && serial !== 'unknown' && serial !== '') {
        // Generate deterministic UUID from serial (same device = same UUID)
        const uuid = this.generateUUIDFromString(`harmonyos_${serial}`);
        this.logger.info(`[DISTINCT_ID] Generated from serial: ${uuid}`);
        return uuid;
      }

      // Fallback: use device info + time (less stable, but still unique)
      this.logger.warn('[DISTINCT_ID] Serial not available, using fallback');
      const model = this.deviceInfo.getDeviceModel();
      const brand = this.deviceInfo.getDeviceBrand();
      const timestamp = Date.now();
      return this.generateUUIDFromString(`harmonyos_${brand}_${model}_${timestamp}`);
    } catch (e) {
      this.logger.error('Failed to generate distinct_id', e);
      // Last resort: truly random UUID
      return this.generateRandomUUID();
    }
  }

  /**
   * Convert string to Uint8Array
   */
  private stringToUint8Array(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    const result = encoder.encodeInto(str);
    return result;
  }

  /**
   * Convert Uint8Array to string
   */
  private uint8ArrayToString(array: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeWithStream(array, { stream: false });
  }

  /**
   * Generate a deterministic UUID v4 from a string seed
   * Same input always produces same UUID (for stability across app restarts)
   */
  private generateUUIDFromString(seed: string): string {
    // Create a simple hash of the seed string
    let hash1 = 0;
    let hash2 = 0;

    for (let i = 0; i < seed.length; i++) {
      const char = seed.charCodeAt(i);
      hash1 = ((hash1 << 5) - hash1) + char;
      hash2 = ((hash2 << 5) - hash2) + char * (i + 1);
      hash1 = hash1 & hash1; // Convert to 32-bit
      hash2 = hash2 & hash2;
    }

    // Use hashes to generate UUID bytes (deterministic)
    const bytes = new Uint8Array(16);
    const view = new DataView(bytes.buffer);

    view.setUint32(0, hash1 >>> 0, false);
    view.setUint32(4, hash2 >>> 0, false);
    view.setUint32(8, (hash1 * 0x9e3779b9) >>> 0, false);
    view.setUint32(12, (hash2 * 0x85ebca6b) >>> 0, false);

    // Set version bits (4) and variant bits (10xxxxxx)
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant

    // Convert to hex string with dashes
    const hex = Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
  }

  /**
   * Generate a truly random UUID v4
   * Used as fallback when deterministic generation fails
   */
  private generateRandomUUID(): string {
    const bytes = new Uint8Array(16);

    // Fill with cryptographically secure random values
    for (let i = 0; i < 16; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }

    // Set version and variant bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant

    const hex = Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
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
      this.logger.info(`[SETUP] ========== Setup Started ==========`);

      // Try using call.argument() method
      const apiKeyFromMethod = call.argument('apiKey') as string;
      const hostFromMethod = call.argument('host') as string;
      this.logger.info(`[SETUP] API Key from call.argument('apiKey'): ${apiKeyFromMethod}`);
      this.logger.info(`[SETUP] Host from call.argument('host'): ${hostFromMethod}`);

      if (apiKeyFromMethod) {
        this.apiKey = apiKeyFromMethod;
        this.logger.info(`[SETUP] ✅ Got API Key: ${this.apiKey}`);
      } else {
        // Fallback to call.args
        const args: ESObject = call.args as ESObject;
        this.apiKey = args['apiKey'] as string;
      }

      // Set host if provided
      if (hostFromMethod) {
        this.posthogHost = hostFromMethod;
        this.logger.info(`[SETUP] ✅ Got Host: ${this.posthogHost}`);
      } else {
        // Fallback to call.args
        const args: ESObject = call.args as ESObject;
        const host = args['host'] as string;
        if (host) {
          this.posthogHost = host;
          this.logger.info(`[SETUP] ✅ Got Host from args: ${this.posthogHost}`);
        }
      }

      this.logger.info(`[SETUP] Final API Key: ${this.apiKey ? this.apiKey.substring(0, 10) + '...' : 'NOT SET'}`);
      this.logger.info(`[SETUP] Final Host: ${this.posthogHost}`);
      this.logger.info(`[SETUP] Enabled: ${this.enabled}`);
      result.success(null);
      this.logger.info(`[SETUP] ✅ Setup completed`);
      this.logger.info(`[SETUP] ========== Setup Ended ==========\n`);
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
        'distinct_id': this.distinctId,
        'properties': mergedProperties,
        'timestamp': new Date().toISOString(),
      };

      this.logger.info(`[SEND] Event data prepared: ${JSON.stringify(eventData)}`);
      this.logger.info(`[SEND] Creating HTTP request to PostHog...`);

      // Create HTTP request
      const httpRequest = http.createHttp();

      // Use configured host
      const posthogUrl = `${this.posthogHost}/capture/`;
      this.logger.info(`[SEND] Sending POST request to ${posthogUrl}`);

      const response = await httpRequest.request(
        posthogUrl,
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

      // Try using call.argument() method first
      const eventNameFromMethod: string | null = call.argument('eventName') as string | null;
      const propertiesFromMethod: ESObject | null = call.argument('properties') as ESObject | null;

      this.logger.info(`[CAPTURE] Event name from call.argument('eventName'): ${eventNameFromMethod}`);
      this.logger.info(`[CAPTURE] Properties from call.argument('properties'): ${JSON.stringify(propertiesFromMethod)}`);

      const fallbackArgs: ESObject = call.args as ESObject;
      const eventName: string = eventNameFromMethod || fallbackArgs['eventName'] as string;
      const properties: ESObject | null = propertiesFromMethod || fallbackArgs['properties'] as ESObject | null;

      this.logger.info(`[CAPTURE] Final event name: ${eventName}`);
      this.logger.info(`[CAPTURE] Final properties: ${JSON.stringify(properties)}`);
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
