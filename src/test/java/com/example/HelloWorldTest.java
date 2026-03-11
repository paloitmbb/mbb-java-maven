package com.example;

import org.junit.Test;
import static org.junit.Assert.*;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;

/**
 * Unit tests for HelloWorld
 */
public class HelloWorldTest {

    @Test
    public void testGetGreetingWithName() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting("Java");
        assertEquals("Hello, Java!", result);
    }

    @Test
    public void testGetGreetingWithNull() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting(null);
        assertEquals("Hello, World!", result);
    }

    @Test
    public void testGetGreetingWithEmptyString() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting("");
        assertEquals("Hello, World!", result);
    }

    @Test
    public void testGetGreetingWithWhitespace() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting("   ");
        assertEquals("Hello,    !", result);
    }

    @Test
    public void testGetGreetingWithSpecialCharacters() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting("@John#123");
        assertEquals("Hello, @John#123!", result);
    }

    @Test
    public void testGetGreetingWithLongName() {
        HelloWorld hello = new HelloWorld();
        String longName = "VeryLongNameToTestMaximumLengthHandling";
        String result = hello.getGreeting(longName);
        assertEquals("Hello, VeryLongNameToTestMaximumLengthHandling!", result);
    }

    @Test
    public void testMainMethodInterruption() {
        ByteArrayOutputStream errContent = new ByteArrayOutputStream();
        PrintStream originalErr = System.err;

        try {
            System.setErr(new PrintStream(errContent));
            // Interrupt the current thread to trigger the catch block in HelloWorld.main
            Thread.currentThread().interrupt();
            HelloWorld.main(new String[]{});

            String errOutput = errContent.toString();
            assertTrue(errOutput.contains("Loop interrupted"));
        } finally {
            System.setErr(originalErr);
            // Clear interrupt status
            Thread.interrupted();
        }
    }

    @Test
    public void testMainMethodNormalExecution() throws Exception {
        // Since the loop runs for 300s, we can't easily wait for it in a unit test.
        // However, we want to cover the happy path start of the loop.
        // We could potentially refactor the main method to accept a loop count,
        // but since we are editing the TEST file per instructions, we will focus
        // on ensuring the core logic is covered.
        ByteArrayOutputStream outContent = new ByteArrayOutputStream();
        PrintStream originalOut = System.out;

        try {
            System.setOut(new PrintStream(outContent));

            // Run a separate thread to execute main and interrupt it quickly
            Thread mainThread = new Thread(() -> HelloWorld.main(new String[]{}));
            mainThread.start();
            Thread.sleep(100); // Give it a moment to start and log the first iteration
            mainThread.interrupt();
            mainThread.join();

            String output = outContent.toString();
            assertTrue(output.contains("Starting 300-second loop..."));
            assertTrue(output.contains("Hello, World!"));
        } finally {
            System.setOut(originalOut);
        }
    }
}
