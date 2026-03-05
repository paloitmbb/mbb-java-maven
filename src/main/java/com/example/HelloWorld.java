package com.example;


/**

 * A simple Hello World application

 */

public class HelloWorld {



    public static void main(String[] args) {

        System.out.println("Hello, World!");

        System.out.println("This is a test Java Maven project for CI/CD pipeline testing.");

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