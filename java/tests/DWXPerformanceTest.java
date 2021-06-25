import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Arrays;
import org.junit.Assert;
import org.junit.Test;
import org.junit.Before;

import api.Client;
import api.EventHandler;

import static api.Helpers.*;



/*

Performance Test

This test will measure how long it takes to open, modify and close pending orders. 
It will open 100 pending orders and calculate the average durations. 

Please don't run this on your live account. 

The MT4/5 server must be initialized with MaximumOrders>=100. 


compile and run:

javac -cp ".;../;../libs/*" DWXPerformanceTest.java
java -cp ".;../;../libs/*" DWXPerformanceTest


JSON jar from here:
https://github.com/junit-team/junit4/wiki/Download-and-Install

*/

public class DWXPerformanceTest {
    
	final static String MetaTraderDirPath = "C:/Users/asd/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/";
	// final static String MetaTraderDirPath = "D:/MetaTrader5_portable/MQL5/Files/";
	final static int sleepDelay = 5;  // 5 milliseconds
	final static int maxRetryCommandSeconds = 10;
	final static boolean loadOrdersFromFile = true;
	final static boolean verbose = true;
	
	
    public static void main(String args[]) throws Exception {
        
        MyEventHandler eventHandler = new MyEventHandler();
        
        Client dwx = new Client(eventHandler, MetaTraderDirPath, sleepDelay, 
                                maxRetryCommandSeconds, loadOrdersFromFile, verbose);
        
    }
}

class MyEventHandler implements EventHandler {
	
	int n = 100;
    String symbol = "EURUSD";
    double entryPrice = 1.17;
	
	long beforeOpen = System.currentTimeMillis();
    long openDuration = -100;
	boolean testStarted = false;
	int nModified = 0;
	long modifyDuration = -100;
    long beforeModification = System.currentTimeMillis();
	long beforeClose = System.currentTimeMillis();
	
    
    public void start(Client dwx) {
        
		print("\nAccount info:\n" + dwx.accountInfo + "\n");
		
        dwx.closeAllOrders();
        while(dwx.openOrders.length() != 0)
            sleep(1000);

        testStarted = true;
        
        for (int i=0; i<n; i++)
            dwx.openOrder(symbol, "buylimit", 0.01, entryPrice, 0, 0, 0, "", 0);
        
        
        while(dwx.openOrders.length() < n)
            sleep(1000);
        
        beforeModification = System.currentTimeMillis();
		for (String ticket : dwx.openOrders.keySet())
            dwx.modifyOrder(Integer.valueOf(ticket), 0.01, 0, entryPrice-0.01, 0, 0);
        
        sleep(1000);

        beforeClose = System.currentTimeMillis();
        for (String ticket : dwx.openOrders.keySet())
            dwx.closeOrder(Integer.valueOf(ticket));
    }
    
	
    public synchronized void onTick(Client dwx, String symbol, double bid, double ask) {
        
		print("onTick: " + symbol + " | bid: " + bid + " | ask: " + ask);
    }
	
    
    public synchronized void onBarData(Client dwx, String symbol, String timeFrame, String time, double open, double high, double low, double close, int tickVolume) {
        
		print("onBarData: " + symbol + ", " + timeFrame + ", " + time + ", " + open + ", " + high + ", " + low + ", " + close + ", " + tickVolume);
    }
	
	
	public synchronized void onHistoricData(Client dwx, String symbol, String timeFrame, JSONObject data) {
        
		// you can also access historic data via: dwx.historicData
		print("onHistoricData: " + symbol + ", " + timeFrame + ", " + data);
    }
	
    
    public synchronized void onMessage(Client dwx, JSONObject message) {
		
        if (message.get("type").equals("ERROR")) {
			print(message.get("type") + " | " + message.get("error_type") + " | " + message.get("description"));
		} else if (message.get("type").equals("INFO")) {
			print(message.get("type") + " | " + message.get("message"));
			
			if (((String)message.get("message")).contains("modified")) {
                nModified++;
                if (nModified == n)
                    modifyDuration = System.currentTimeMillis() - beforeModification;
			}
		}
    }
	
    
    // triggers when an order is added or removed, not when only modified. 
    public synchronized void onOrderEvent(Client dwx) {
		
        print("onOrderEvent:");
        
        // dwx.openOrders is a JSONObject, which can be accessed like this:
        for (String ticket : dwx.openOrders.keySet()) 
            print(ticket + ": " + dwx.openOrders.get(ticket));
		
		
		if (!testStarted)
            return;
        
        if (dwx.openOrders.length() == n) {
            openDuration = System.currentTimeMillis() - beforeOpen;
        } else if (dwx.openOrders.length() == 0) {
            long closeDuration = System.currentTimeMillis() - beforeClose;
            print("\nopenDuration: " + openDuration/n + " milliseconds per order");
            print("modifyDuration: " + modifyDuration/n + " milliseconds per order");
            print("closeDuration: " + closeDuration/n + " milliseconds per order");
		}
    }
}

