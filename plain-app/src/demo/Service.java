package demo;

import java.util.List;

/** The class the stand-in agent rewrites in 02-java-agent. */
public class Service {

    public String call() {
        return String.join(",", List.of("a", "b"));
    }
}
