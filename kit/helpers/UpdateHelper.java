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
