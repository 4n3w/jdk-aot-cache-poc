package demo;

import org.apache.geode.cache.Region;
import org.apache.geode.cache.client.ClientCache;
import org.apache.geode.cache.client.ClientCacheFactory;
import org.apache.geode.cache.client.ClientRegionShortcut;
import org.apache.geode.pdx.ReflectionBasedAutoSerializer;

/**
 * A GemFire Java client that does what a client application does at startup: creates a ClientCache
 * with a locator pool and subscriptions, creates a region, registers interest, and does puts and a
 * get with PDX auto-serialization. It prints one RESULT line with how long each part took.
 *
 * If no cluster is reachable the cache and region are still created, and the operations fail. That
 * is the "blind" training run in client-test.sh.
 */
public class GemFireClient {

    public static class Item {
        public String id;
        public String name;
        public int quantity;

        public Item() {
        }

        public Item(String id, String name, int quantity) {
            this.id = id;
            this.name = name;
            this.quantity = quantity;
        }
    }

    public static void main(String[] args) {
        String locatorHost = System.getProperty("locator.host", "localhost");
        int locatorPort = Integer.getInteger("locator.port", 10334);

        long start = System.nanoTime();
        ClientCache cache = new ClientCacheFactory()
                .addPoolLocator(locatorHost, locatorPort)
                .setPoolMinConnections(2)
                .setPoolSubscriptionEnabled(true)
                .setPdxSerializer(new ReflectionBasedAutoSerializer("demo\\..*"))
                .set("log-level", "warn")
                .create();
        Region<String, Object> region = cache
                .<String, Object>createClientRegionFactory(ClientRegionShortcut.PROXY)
                .create("demo");
        long created = System.nanoTime();

        String status;
        try {
            region.registerInterestForAllKeys();
            for (int i = 0; i < 20; i++) {
                region.put("k" + i, new Item("k" + i, "name" + i, i));
            }
            Item item = (Item) region.get("k7");
            status = "operations OK, read back " + item.name;
        } catch (Exception e) {
            status = "operations FAILED: " + e.getClass().getSimpleName();
        }
        long done = System.nanoTime();

        System.out.printf("RESULT cacheCreate=%dms operations=%dms  %s%n",
                (created - start) / 1_000_000, (done - created) / 1_000_000, status);
        cache.close();
    }
}
