package demo;

import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/**
 * The smallest application that gives the JVM something to cache: three classes, a record, a lambda
 * and a stream. It starts in a few tens of milliseconds, so a test can train and run it many times.
 */
public class Main {

    public static void main(String[] args) {
        List<String> names = IntStream.range(0, 50)
                .mapToObj(i -> new Helper(i).name())
                .collect(Collectors.toList());
        System.out.println("app ran: " + names.size() + " helpers, service says " + new Service().call());
    }
}
