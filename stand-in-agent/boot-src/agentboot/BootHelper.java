package agentboot;

/**
 * The only class in agent-boot.jar, the jar the stand-in agent appends to the bootstrap class path
 * when asked to (appendboot=...). Monitoring agents commonly ship such a jar so that classes loaded by
 * the bootstrap loader can call into them.
 */
public final class BootHelper {

    private BootHelper() {
    }
}
