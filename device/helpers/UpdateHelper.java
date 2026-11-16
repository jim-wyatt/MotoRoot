/*
 * UpdateHelper: cancel a staged A/B firmware update through Android's own UpdateEngine API.
 *
 * Why it exists. On the tested device a Motorola OTA can finish downloading and stage
 * itself on the inactive slot during first setup, so the next reboot would switch to newer,
 * untested firmware. Android's update_engine exposes resetStatus() for exactly this case:
 * it cancels the completed update and removes its snapshots. The class is not in the public
 * SDK, so this program reaches it by reflection at runtime instead of compiling against it,
 * which is also why no SDK jar is needed to build it (see dev/Build-Device.ps1).
 *
 * How it is run. Pushed to the device as a bare DEX and launched with app_process as root
 * (docs/device/walkthrough.md, Stage 4):
 *
 *   CLASSPATH=/data/local/tmp/moto-update-helper.dex app_process /system/bin UpdateHelper inspect
 *   CLASSPATH=/data/local/tmp/moto-update-helper.dex app_process /system/bin UpdateHelper reset-status
 *
 *   inspect       prints the reset/cancel method signatures UpdateEngine offers; changes nothing.
 *   reset-status  performs the cancellation. The misc partition must be writable for it to
 *                 succeed; the walkthrough makes it writable for just this call.
 *
 * It deliberately offers nothing else: no slot selection, no raw boot-metadata edits.
 *
 * Derived from parsimo2010's guide kit (MIT); see NOTICE.md.
 */
public final class UpdateHelper {
  public static void main(String[] args) throws Exception {
    Class<?> cls = Class.forName("android.os.UpdateEngine");
    if (args.length != 1) throw new IllegalArgumentException("inspect or reset-status required");
    if (args[0].equals("inspect")) {
      for (java.lang.reflect.Method method : cls.getDeclaredMethods()) {
        if (method.getName().contains("reset") || method.getName().equals("cancel"))
          System.out.println(method.toString());
      }
      return;
    }
    if (!args[0].equals("reset-status")) throw new IllegalArgumentException("Unknown command");
    Object engine = cls.getConstructor().newInstance();
    cls.getMethod("resetStatus").invoke(engine);
    System.out.println("UpdateEngine.resetStatus returned successfully");
  }
}
