package com.example;

//  Test vulnerabilities for CodeQL analysis

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Random;

//  Test vulnerabilities end


/**

 * A simple Hello World application

 */

public class HelloWorld {

    /**
     * TEST VULNERABILITY 1 — HIGH (SQL Injection)
     * CodeQL: java/sql-injection
     * User input concatenated directly into SQL query — never do this in production.
     * @param userName untrusted user input
     */
    public void unsafeQuery(String userName) throws Exception {
        Connection conn = DriverManager.getConnection("jdbc:h2:mem:test");
        Statement stmt = conn.createStatement();
        // HIGH: SQL injection — user input concatenated directly into query
        ResultSet rs = stmt.executeQuery("SELECT * FROM users WHERE name = '" + userName + "'");
        rs.close();
        stmt.close();
        conn.close();
    }

    /**
     * TEST VULNERABILITY 2 — LOW (Predictable random seed)
     * CodeQL: java/predictable-random
     * Using java.util.Random for security-sensitive context is weak.
     * @return predictable token
     */
    public String weakToken() {
        // LOW: predictable random — not cryptographically secure
        Random random = new Random(12345);
        return String.valueOf(random.nextInt());
    }

//    Test Vulnerability end

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

        if (name == null || name.isBlank()) {

            return "Hello, World!";

        }

        return "Hello, " + name.trim() + "!";

    }

}
