import { uiContext } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from './Logger';

/**
 * Device Information Utility
 * Provides device and system information for PostHog analytics
 */
export class DeviceInfo {
  private logger: Logger = new Logger('DeviceInfo');

  /**
   * Get device model information
   */
  getDeviceModel(): string {
    try {
      return deviceInfo.productModel;
    } catch (e) {
      this.logger.error('Failed to get device model', e);
      return 'Unknown';
    }
  }

  /**
   * Get device brand/manufacturer
   */
  getDeviceBrand(): string {
    try {
      return deviceInfo.brand;
    } catch (e) {
      this.logger.error('Failed to get device brand', e);
      return 'Unknown';
    }
  }

  /**
   * Get OS version
   */
  getOSVersion(): string {
    try {
      return `HarmonyOS ${deviceInfo.osFullName}`;
    } catch (e) {
      this.logger.error('Failed to get OS version', e);
      return 'HarmonyOS Unknown';
    }
  }

  /**
   * Get device SDK version
   */
  getSdkVersion(): number {
    try {
      return deviceInfo.sdkApiVersion;
    } catch (e) {
      this.logger.error('Failed to get SDK version', e);
      return 0;
    }
  }

  /**
   * Get screen density
   */
  getScreenDensity(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return displayInfo.densityDPI / 160;
    } catch (e) {
      this.logger.error('Failed to get screen density', e);
      return 2.0;
    }
  }

  /**
   * Get screen width in pixels
   */
  getScreenWidth(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return displayInfo.width;
    } catch (e) {
      this.logger.error('Failed to get screen width', e);
      return 1080;
    }
  }

  /**
   * Get screen height in pixels
   */
  getScreenHeight(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return displayInfo.height;
    } catch (e) {
      this.logger.error('Failed to get screen height', e);
      return 2400;
    }
  }

  /**
   * Get complete device information as a map
   */
  getDeviceInfo(): Record<string, Object> {
    return {
      'manufacturer': this.getDeviceBrand(),
      'deviceModel': this.getDeviceModel(),
      'osVersion': this.getOSVersion(),
      'sdkVersion': this.getSdkVersion(),
      'screenWidth': this.getScreenWidth(),
      'screenHeight': this.getScreenHeight(),
      'screenDensity': this.getScreenDensity(),
      'platform': 'HarmonyOS',
    };
  }

  /**
   * Get PostHog specific device properties
   */
  getPosthogDeviceProperties(): Record<string, Object> {
    const info = this.getDeviceInfo();
    return {
      '\$manufacturer': info['manufacturer'],
      '\$device_model': info['deviceModel'],
      '\$os': 'HarmonyOS',
      '\$os_version': info['osVersion'],
      '\$screen_height': info['screenHeight'],
      '\$screen_width': info['screenWidth'],
      '\$device_type': 'mobile',
      '\$lib': 'posthog-flutter',
      '\$lib_version': '5.13.0-harmonyos.1',
    };
  }
}
