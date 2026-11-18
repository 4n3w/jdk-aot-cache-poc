package demo;

public record Helper(int number) {

    public String name() {
        return "h" + number;
    }
}
