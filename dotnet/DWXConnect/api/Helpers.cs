using System;
using System.IO;
using System.Globalization;


/*Helpers class

This class includes helper functions for printing, formatting and file operations. 

*/

namespace DWXConnect
{
    public class Helpers
    {
		
		/*Prints to console output. 
		
		Args:
			obj (Object): Object to print. 
		
		*/
		public static void print(object obj)
        {
            Console.WriteLine(obj);
        }
		

		/*Tries to write to a file. 
		
		Args:
			filePath (string): file path of the file.
			text (string): text to write. 
		
		*/
        public static bool tryWriteToFile(string filePath, string text)
        {
            try
            {
                File.WriteAllText(filePath, text);
                return true;
            }
            catch
            {
                return false;
            }
        }
		

		/*Tries to delete a file. 
		
		Args:
			filePath (string): file path of the file.
		
		*/
        public static void tryDeleteFile(string path)
        {
            try
            {
                File.Delete(path);
            }
            catch
            {
            }
        }
		
		
	/*Formats a double value to string. 
	
	Args:
		value (double): numeric value to format.
	
	*/
	public static string format(double value)
        {
            return value.ToString("G", CultureInfo.CreateSpecificCulture("en-US"));
        }

	/*Tries to read a file and handles various exceptions which then return an empty string and writes the exception to the console.
	
 	*/
	public static string tryReadFile(string path)
    	{
	        try
	        {
	            return File.ReadAllText(path);
	        }
	        catch (DirectoryNotFoundException)
	        {
	            Console.WriteLine("api.Helpers.tryReadFile | DirectoryNotFoundException. Returning empty string.");
	            return "";
	        }
	        catch (FileNotFoundException)
	        {
	            Console.WriteLine($"api.Helpers.tryReadFile | FileNotFoundException. Creating empty file at path ({path}) & returning empty string.");
	            CreateEmptyFile(path);
	            return "";
	        }
	        catch (IOException)
	        {
	            Console.WriteLine("api.Helpers.tryReadFile | IOException. Race condition. Most likely this process and the MetaTrader EA both trying to access/use the file simultaneously. Returning empty string.");
	            return "";
	        }
    	}

	private static void CreateEmptyFile(string filepath)
    	{
		File.Create(filepath).Dispose();
    	}
    }
}
