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
    public void testMainMethod() {
        ByteArrayOutputStream outContent = new ByteArrayOutputStream();
        PrintStream originalOut = System.out;
        
        try {
            System.setOut(new PrintStream(outContent));
            HelloWorld.main(new String[]{});
            String output = outContent.toString();
            
            assertTrue(output.contains("Hello, World!"));
            assertTrue(output.contains("This is a test Java Maven project for CI/CD pipeline testing."));
        } finally {
            System.setOut(originalOut);
        }
    }
}
