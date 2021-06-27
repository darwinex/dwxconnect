import org.json.JSONArray;
import org.json.JSONObject;
import java.io.FileReader;

import api.Client;
import api.EventHandler;

import static api.Helpers.*;

/*

Example DWX_Connect client in java


This example client will subscribe to tick data and bar data. 
It will also request historic data. 

compile and run:

javac -cp ".;libs/*" "@sources.txt" 
java -cp ".;libs/*" DWXExampleClient


JSON jar from here:
https://mvnrepository.com/artifact/org.json/json
or:
https://github.com/stleary/JSON-java

*/

public class DWXExampleClient {
    
	final static String MetaTraderDirPath = "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/";
	
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


/*Custom event handler implementing the EventHandler interface. 
*/
class MyEventHandler implements EventHandler {
	
	boolean first = true;
    
    public void start(Client dwx) {
        
		// account information is stored in dwx.accountInfo.
		print("\nAccount info:\n" + dwx.accountInfo + "\n");
		
        // subscribe to tick data:
		String[] symbols = {"EURUSD", "GBPUSD"};
        dwx.subscribeSymbols(symbols);
        
		// subscribe to bar data:
        String[][] symbolsBarData = {{"EURUSD", "M1"}, {"AUDCAD", "M5"}, {"GBPCAD", "M15"}};
        dwx.subscribeSymbolsBarData(symbolsBarData);
		
		// request historic data:
		long end = System.currentTimeMillis()/1000;
		long start = end - 10*24*60*60;  // last 10 days
		dwx.getHistoricData("AUDCAD", "D1", start, end);
		
		// dwx.closeOrdersByMagic(77);
		// sleep(2000);
    }
	
    
    // use synchronized so that price updates and execution updates are not processed one after the other. 
    public synchronized void onTick(Client dwx, String symbol, double bid, double ask) {
        
		print("onTick: " + symbol + " | bid: " + bid + " | ask: " + ask);
        // print(symbol + " ticks: " + app.history.get(symbol).history.size());
		
		// to open an order:
		// if (first) {
			// first = false;
			// for (int i=0; i<5; i++) {
				// dwx.openOrder(symbol, "buystop", 0.05, ask+0.01, 0, 0, 77, "", 0);
			// }
		// }
    }
	
    
    public synchronized void onBarData(Client dwx, String symbol, String timeFrame, String time, double open, double high, double low, double close, int tickVolume) {
        
		print("onBarData: " + symbol + ", " + timeFrame + ", " + time + ", " + open + ", " + high + ", " + low + ", " + close + ", " + tickVolume);
    }
	
    
    public synchronized void onMessage(Client dwx, JSONObject message) {
		
        if (message.get("type").equals("ERROR")) 
			print(message.get("type") + " | " + message.get("error_type") + " | " + message.get("description"));
		else if (message.get("type").equals("INFO")) 
			print(message.get("type") + " | " + message.get("message"));
    }
	
	public synchronized void onHistoricTrades(Client dwx) {
        
		print("onHistoricTrades: " + dwx.historicTrades);
    }
	
    // triggers when an order is added or removed, not when only modified. 
    public synchronized void onOrderEvent(Client dwx) {
		
        print("onOrderEvent:");
        
        // dwx.openOrders is a JSONObject, which can be accessed like this:
        for (String ticket : dwx.openOrders.keySet()) 
            print(ticket + ": " + dwx.openOrders.get(ticket));
    }
	
	
	public synchronized void onHistoricData(Client dwx, String symbol, String timeFrame, JSONObject data) {
        
		// you can also access historic data via: dwx.historicData
		print("onHistoricData: " + symbol + ", " + timeFrame + ", " + data);
    }
}

