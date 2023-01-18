using System;
using System.IO;
using Newtonsoft.Json.Linq;
using static DWXConnect.Helpers;

/*

Example DWXConnect client in C#


This example client will subscribe to tick data and bar data. 
It will also request historic data. 


compile and run:

dotnet build
dotnet run

*/

namespace DWXConnect
{
    class DWXExampleClient
    {
        static string MetaTraderDirPath = "C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/";
		
        static int sleepDelay = 5;  // 5 milliseconds
        static int maxRetryCommandSeconds = 10;
        static bool loadOrdersFromFile = true;
        static bool verbose = true;

        static void Main(string[] args)
        {

            MyEventHandler eventHandler = new MyEventHandler();

            Client dwx = new Client(eventHandler, MetaTraderDirPath, sleepDelay,
                                    maxRetryCommandSeconds, loadOrdersFromFile, verbose);
        }
    }

	
	/*Custom event handler implementing the EventHandler interface. 
	*/
    class MyEventHandler : EventHandler
    {
        bool first = true;

        public void start(Client dwx)
        {
			// account information is stored in dwx.accountInfo.
			print("\nAccount info:\n" + dwx.accountInfo + "\n");
		
			// subscribe to tick data:
            string[] symbols = { "EURUSD", "GBPUSD"};
            dwx.subscribeSymbols(symbols);
			
			// subscribe to bar data:
			string[,] symbolsBarData = new string[,]{ { "EURUSD", "M1" }, { "AUDCAD", "M5" }, { "GBPCAD", "M15" } };
             dwx.subscribeSymbolsBarData(symbolsBarData);
			
			// request historic data:
			long end = DateTimeOffset.Now.ToUnixTimeSeconds();
			long start = end - 10*24*60*60;  // last 10 days
			dwx.getHistoricData("EURUSD", "D1", start, end);
			
        }

        public void onTick(Client dwx, string symbol, double bid, double ask)
        {
            print("onTick: " + symbol + " | bid: " + bid + " | ask: " + ask);
			
			// print(dwx.accountInfo);
			// print(dwx.openOrders);
            
            // to open a few orders:
			// if (first) {
			// 	first = false;
            // // dwx.closeAllOrders();
			// 	for (int i=0; i<5; i++) {
			// 		dwx.openOrder(symbol, "buystop", 0.05, ask+0.01, 0, 0, 77, "", 0);
			// 	}
			// }
        }

        public void onBarData(Client dwx, string symbol, string timeFrame, string time, double open, double high, double low, double close, int tickVolume)
        {
            print("onBarData: " + symbol + ", " + timeFrame + ", " + time + ", " + open + ", " + high + ", " + low + ", " + close + ", " + tickVolume);

            foreach (var x in dwx.historicData)
                print(x.Key + ": " + x.Value);
        }

        public void onHistoricData(Client dwx, String symbol, String timeFrame, JObject data)
        {

            // you can also access historic data via: dwx.historicData.keySet()
            print("onHistoricData: " + symbol + ", " + timeFrame + ", " + data);
        }

        public void onHistoricTrades(Client dwx)
        {
            print("onHistoricTrades: " + dwx.historicTrades);
        }


        public void onMessage(Client dwx, JObject message)
        {
            if (((string)message["type"]).Equals("ERROR")) 
				print(message["type"] + " | " + message["error_type"] + " | " + message["description"]);
			else if (((string)message["type"]).Equals("INFO")) 
				print(message["type"] + " | " + message["message"]);
        }

        public void onOrderEvent(Client dwx)
        {
            print("onOrderEvent: " + dwx.openOrders.Count + " open orders");

            // dwx.openOrders is a JSONObject, which can be accessed like this:
            // foreach (var x in dwx.openOrders)
            //     print(x.Key + ": " + x.Value);
        }
    }
}
