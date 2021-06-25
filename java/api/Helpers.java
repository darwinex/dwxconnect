package api;

import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Date;
import java.util.TimeZone;
import java.util.concurrent.ConcurrentHashMap;
import java.text.SimpleDateFormat;
import java.text.ParseException;


/*Helpers class

This class includes helper functions for printing, formatting and file operations. 

*/

public class Helpers {
    
	/*Prints to console output. 
	
	Args:
		obj (Object): Object to print. 
	
	*/
    public static void print(Object obj) {
        System.out.println(obj);
    }
	
    
	/*Tries to sleep for a given time period. 
	
	Args:
		millis (int): milliseconds to sleep. 
	
	*/
    public static void sleep(int millis) {
        try {
            Thread.sleep(millis);
        } catch (Exception e) {
        }
    }
	
    
	/*Tries to read a file. 
	
	Args:
		filePath (String): file path of the file.
	
	*/
    public static String tryReadFile(String filePath) {
        
        final File f = new File(filePath);
        if(!f.exists()) {
            // print("ERROR: file does not exist: " + filePath);
            return "";
        }
        
        try{
            Path path = Paths.get(filePath);
            return Files.readString(path);  // , StandardCharsets.US_ASCII
        } catch (Exception e) {
			// e.printStackTrace();
            return "";
		}
    }
	
    
    /*Tries to write to a file. 
	
	Args:
		filePath (String): file path of the file.
		text (String): text to write. 
	
	*/
    public static boolean tryWriteToFile(String filePath, String text) {
        try {
            Files.write(Paths.get(filePath), text.getBytes());
            return true;
        } catch (Exception e) {
            // e.printStackTrace();
            return false;
        }
    }
	
    
	/*Tries to delete a file. 
	
	Args:
		filePath (String): file path of the file.
	
	*/
    public static boolean tryDeleteFile(String filePath) {
        try {
            Files.deleteIfExists(Paths.get(filePath));
            return true;
        } catch (Exception e) {
            // e.printStackTrace();
            return false;
        }
    }
}
