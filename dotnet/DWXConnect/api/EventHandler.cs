using Newtonsoft.Json.Linq;


/*EventHandler Interface

This interfance can be used to define what should happen when 
specific events happen, like new ticks or orders. 
An example implementation can be found in DWXExampleClient.cs. 
*/

namespace DWXConnect
{
    public interface EventHandler
    {

        public void start(Client dwx);

        public void onTick(Client dwx, string symbol, double bid, double ask);

        public void onBarData(Client dwx, string symbol, string timeFrame, string time, double open, double high, double low, double close, int tickVolume);

        public void onHistoricData(Client dwx, string symbol, string timeFrame, JObject data);

        public void onHistoricTrades(Client dwx);

        public void onMessage(Client dwx, JObject message);

        public void onOrderEvent(Client dwx);

    }
}