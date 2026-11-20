/*
 * UpdaterCleanup: remove the Motorola updater's scheduled restart alarm and its notification.
 *
 * Why it exists. After a staged update is cancelled with UpdateHelper, Motorola Software
 * Update (com.motorola.ccc.ota) can still hold an alarm that would restart the device at a
 * deadline, and a notification claiming an update is waiting. Those are the app's own state,
 * separate from update_engine. This program asks the system's alarm and notification
 * services to drop everything that belongs to that package.
 *
 * How it is run. Pushed as a bare DEX, made read-only (Android rejects a writable DEX run as
 * an app uid), and launched with app_process AS THE UPDATER'S OWN UID, so the services treat
 * the request as the package's own (docs/device/walkthrough.md, Stage 4):
 *
 *   su <updater uid> -c 'CLASSPATH=/data/local/tmp/moto-updater-cleanup.dex app_process /system/bin UpdaterCleanup inspect'
 *   su <updater uid> -c 'CLASSPATH=/data/local/tmp/moto-updater-cleanup.dex app_process /system/bin UpdaterCleanup cancel'
 *
 *   inspect  prints the relevant IAlarmManager / INotificationManager signatures; changes nothing.
 *   cancel   removes the package's alarms, then cancels its notifications.
 *
 * Discover the uid on the device (pm list packages -U com.motorola.ccc.ota); never hard-code
 * one. This is a one-off cleanup of app state, not a durable updater block; the
 * wifi_ota_guard module is the durable block.
 *
 * Derived from parsimo2010's guide kit (MIT); see NOTICE.md.
 */
public final class UpdaterCleanup {
  public static void main(String[] args) throws Exception {
    String pkg = "com.motorola.ccc.ota";
    // Hidden system classes, reached by reflection: ServiceManager hands out raw binders,
    // and each service's Stub.asInterface wraps one in its AIDL interface.
    Class<?> sm = Class.forName("android.os.ServiceManager");
    Class<?> binder = Class.forName("android.os.IBinder");
    Object alarmBinder = sm.getMethod("getService", String.class).invoke(null, "alarm");
    Class<?> alarmStub = Class.forName("android.app.IAlarmManager$Stub");
    Object alarm = alarmStub.getMethod("asInterface", binder).invoke(null, alarmBinder);
    Class<?> api = Class.forName("android.app.IAlarmManager");
    if (args.length == 0 || args[0].equals("inspect")) {
      for (java.lang.reflect.Method m : api.getMethods()) if (m.getName().contains("remove")) System.out.println(m);
      Class<?> n = Class.forName("android.app.INotificationManager");
      for (java.lang.reflect.Method m : n.getMethods()) if (m.getName().equals("cancelAllNotifications")) System.out.println(m);
      return;
    }
    if (!args[0].equals("cancel")) throw new IllegalArgumentException();
    api.getMethod("removeAll", String.class).invoke(alarm, pkg);
    System.out.println("Updater alarms removed");
    Object nb = sm.getMethod("getService", String.class).invoke(null, "notification");
    Object n = Class.forName("android.app.INotificationManager$Stub").getMethod("asInterface", binder).invoke(null, nb);
    Class.forName("android.app.INotificationManager").getMethod("cancelAllNotifications", String.class, int.class).invoke(n, pkg, 0);
    System.out.println("Updater notifications removed");
  }
}
