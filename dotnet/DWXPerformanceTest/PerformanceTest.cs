using System;
using System.IO;
using System.Threading;
using Newtonsoft.Json.Linq;
using DWXConnect;
using static DWXConnect.Helpers;

/*

Performance Test

This test will measure how long it takes to open, modify and close pending orders. 
It will open 100 pending orders and calculate the average durations. 

Please don't run this on your live account. 

The MT4/5 server must be initialized with MaximumOrders>=100. 

Compile and run:
dotnet build
dotnet run

*/

namespace DWXConnect
{
    class DWXPerformanceTest
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

    class MyEventHandler : DWXConnect.EventHandler
    {
        int n = 100;
        string symbol = "EURUSD";
        double entryPrice = 1.17;

        long beforeOpen = DateTimeOffset.Now.ToUnixTimeMilliseconds();
        long openDuration = -100;
        bool testStarted = false;
        int nModified = 0;
        long modifyDuration = -100;
        long beforeModification = DateTimeOffset.Now.ToUnixTimeMilliseconds();
        long beforeClose = DateTimeOffset.Now.ToUnixTimeMilliseconds();

        public void start(Client dwx)
        {
            dwx.closeAllOrders();
            while (dwx.openOrders.Count != 0)
                Thread.Sleep(1000);

            testStarted = true;

            for (int i = 0; i < n; i++)
                dwx.openOrder(symbol, "buylimit", 0.01, entryPrice, 0, 0, 0, "", 0);


            while (dwx.openOrders.Count < n)
                Thread.Sleep(1000);

            beforeModification = DateTimeOffset.Now.ToUnixTimeMilliseconds();
            foreach (var x in dwx.openOrders)
                dwx.modifyOrder(Int32.Parse(x.Key), 0.01, 0, entryPrice - 0.01, 0, 0);

            Thread.Sleep(1000);

            beforeClose = DateTimeOffset.Now.ToUnixTimeMilliseconds();
            foreach (var x in dwx.openOrders)
                dwx.closeOrder(Int32.Parse(x.Key));
        }

        public void onTick(Client dwx, string symbol, double bid, double ask)
        {
            print("onTick: " + symbol + " | bid: " + bid + " | ask: " + ask);

            // print(dwx.accountInfo);
            // print(dwx.openOrders);
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

        public void onMessage(Client dwx, JObject message)
        {
            if (((string)message["type"]).Equals("ERROR"))
            {
                print(message["type"] + " | " + message["error_type"] + " | " + message["description"]);
            }
            else if (((string)message["type"]).Equals("INFO"))
            {
                print(message["type"] + " | " + message["message"]);

                if (((string)message["message"]).Contains("modified"))
                {
                    nModified++;
                    if (nModified == n)
                        modifyDuration = DateTimeOffset.Now.ToUnixTimeMilliseconds() - beforeModification;
                }
            }
        }
        public void onOrderEvent(Client dwx)
        {
            print("onOrderEvent: " + dwx.openOrders.Count + " open orders");

            // dwx.openOrders is a JSONObject, which can be accessed like this:
            // foreach (var x in dwx.openOrders)
            //     print(x.Key + ": " + x.Value);
            
            if (!testStarted)
                return;

            if (dwx.openOrders.Count == n)
            {
                openDuration = DateTimeOffset.Now.ToUnixTimeMilliseconds() - beforeOpen;
            }
            else if (dwx.openOrders.Count == 0)
            {
                long closeDuration = DateTimeOffset.Now.ToUnixTimeMilliseconds() - beforeClose;
                print("\nopenDuration: " + openDuration / n + " milliseconds per order");
                print("modifyDuration: " + modifyDuration / n + " milliseconds per order");
                print("closeDuration: " + closeDuration / n + " milliseconds per order");
            }
        }
    }
}
