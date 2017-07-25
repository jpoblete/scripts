package main.java;
import javax.crypto.Cipher;

public class TestUCE {
	public static void main(String args[]) throws Exception {
            boolean unlimited = Cipher.getMaxAllowedKeyLength("RC5") >= 256;
            int maxKeyLen = Cipher.getMaxAllowedKeyLength("AES");
            System.out.println("JCE settings...");
	    System.out.println("Unlimited cryptography enabled: " + unlimited);
	    System.out.println("Maximum Key Length (AES): " + maxKeyLen);
	}
}
