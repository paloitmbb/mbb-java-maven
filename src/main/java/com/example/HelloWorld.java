package com.example;


/**

 * A simple Hello World application

 */

public class HelloWorld {



    public static void main(String[] args) {
        System.out.println("Starting 300-second loop...");
        for (int i = 1; i <= 300; i++) {
            System.out.println("Hello, World!");
            System.out.println("This is a test Java Maven project for CI/CD pipeline testing.");
            System.out.println("Loop iteration: " + i + " (Running for " + i + " seconds)");
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {
                System.err.println("Loop interrupted: " + e.getMessage());
                Thread.currentThread().interrupt();
                break;
            }
        }
        System.out.println("300-second loop completed.");
    }



    /**

     * Returns a greeting message

     * @param name the name to greet

     * @return greeting message

     */

    public String getGreeting(String name) {

        if (name == null || name.isEmpty()) {

            return "Hello, World!";

        }

        return "Hello, " + name + "!";

    }

}
