package agent;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.jar.JarFile;

/**
 * A stand-in for a commercial monitoring agent. It does not change what the application does. It
 * reports what the JVM lets an agent see, because that is what changes when an AOT cache is in use.
 *
 * Options go after the jar path, separated by commas: -javaagent:agent.jar=watch=demo.,retransform
 *
 *   watch=PREFIX    report classes whose name starts with PREFIX one by one (default: demo.)
 *   rewrite=CLASS   hand the JVM new bytes for CLASS, the way an instrumenting agent does
 *   retransform     retransform the watched classes that were loaded before the agent started
 *   appendboot=JAR  append JAR to the bootstrap class path, as many agents do with a helper jar
 */
public final class StandInAgent {

    private static final int LIST_LIMIT = 10;

    private static final AtomicInteger atLoadTime = new AtomicInteger();
    private static final AtomicInteger byRetransformation = new AtomicInteger();

    public static void premain(String args, Instrumentation inst) throws Exception {
        String watch = "demo.";
        String rewrite = null;
        String appendBoot = null;
        boolean retransform = false;
        for (String option : (args == null ? "" : args).split(",")) {
            if (option.startsWith("watch=")) {
                watch = option.substring("watch=".length());
            } else if (option.startsWith("rewrite=")) {
                rewrite = option.substring("rewrite=".length());
            } else if (option.startsWith("appendboot=")) {
                appendBoot = option.substring("appendboot=".length());
            } else if (option.equals("retransform")) {
                retransform = true;
            } else if (!option.isEmpty()) {
                throw new IllegalArgumentException("unknown agent option: " + option);
            }
        }

        if (appendBoot != null) {
            inst.appendToBootstrapClassLoaderSearch(new JarFile(appendBoot));
            log("appended " + appendBoot + " to the bootstrap class path");
        }

        // Everything in this list was loaded before the agent ran, so the hook below never saw it load.
        Class<?>[] loaded = inst.getAllLoadedClasses();
        List<Class<?>> watched = new ArrayList<>();
        for (Class<?> c : loaded) {
            if (c.getName().startsWith(watch)) {
                watched.add(c);
            }
        }
        log("started: " + loaded.length + " classes already loaded, " + watched.size() + " of them " + watch + "*");
        for (int i = 0; i < watched.size() && i < LIST_LIMIT; i++) {
            log("  loaded before the agent started: " + watched.get(i).getName());
        }
        if (watched.size() > LIST_LIMIT) {
            log("  ... and " + (watched.size() - LIST_LIMIT) + " more");
        }

        inst.addTransformer(hook(watch, rewrite), true);

        if (retransform) {
            List<Class<?>> modifiable = new ArrayList<>();
            for (Class<?> c : watched) {
                if (inst.isModifiableClass(c)) {
                    modifiable.add(c);
                }
            }
            log("retransforming " + modifiable.size() + " classes that were loaded before the agent started");
            inst.retransformClasses(modifiable.toArray(new Class<?>[0]));
        }

        Runtime.getRuntime().addShutdownHook(new Thread(() -> log("exit: the hook was offered "
                + atLoadTime.get() + " classes at load time, " + byRetransformation.get() + " by retransformation")));
    }

    /** The agent's class-file hook: the JVM calls it for each class it loads or retransforms. */
    private static ClassFileTransformer hook(String watch, String rewrite) {
        return new ClassFileTransformer() {
            @Override
            public byte[] transform(ClassLoader loader, String internalName, Class<?> classBeingRedefined,
                                    ProtectionDomain domain, byte[] classFile) {
                boolean loading = classBeingRedefined == null;
                (loading ? atLoadTime : byRetransformation).incrementAndGet();
                String name = internalName == null ? "" : internalName.replace('/', '.');
                if (name.startsWith(watch)) {
                    log("hook offered " + name + (loading ? " at load time" : " by retransformation"));
                }
                if (name.equals(rewrite)) {
                    // Any non-null return counts as a rewritten class. The bytes are the same here; a real
                    // agent would return an instrumented copy.
                    log("hook rewrote " + name);
                    return classFile.clone();
                }
                return null;
            }
        };
    }

    private static void log(String message) {
        System.out.println("[agent] " + message);
    }
}
