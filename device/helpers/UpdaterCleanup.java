public final class UpdaterCleanup {
  public static void main(String[] args) throws Exception {
    String pkg="com.motorola.ccc.ota";
    Class<?> sm=Class.forName("android.os.ServiceManager");
    Class<?> binder=Class.forName("android.os.IBinder");
    Object alarmBinder=sm.getMethod("getService",String.class).invoke(null,"alarm");
    Class<?> alarmStub=Class.forName("android.app.IAlarmManager$Stub");
    Object alarm=alarmStub.getMethod("asInterface",binder).invoke(null,alarmBinder);
    Class<?> api=Class.forName("android.app.IAlarmManager");
    if(args.length==0 || args[0].equals("inspect")) {
      for(java.lang.reflect.Method m:api.getMethods()) if(m.getName().contains("remove")) System.out.println(m);
      Class<?> n=Class.forName("android.app.INotificationManager");
      for(java.lang.reflect.Method m:n.getMethods()) if(m.getName().equals("cancelAllNotifications")) System.out.println(m);
      return;
    }
    if(!args[0].equals("cancel")) throw new IllegalArgumentException();
    api.getMethod("removeAll",String.class).invoke(alarm,pkg);
    System.out.println("Updater alarms removed");
    Object nb=sm.getMethod("getService",String.class).invoke(null,"notification");
    Object n=Class.forName("android.app.INotificationManager$Stub").getMethod("asInterface",binder).invoke(null,nb);
    Class.forName("android.app.INotificationManager").getMethod("cancelAllNotifications",String.class,int.class).invoke(n,pkg,0);
    System.out.println("Updater notifications removed");
  }
}
