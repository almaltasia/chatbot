# This files contains your custom actions which can be used to run
# custom Python code.
#
# See this guide on how to implement these action:
# https://rasa.com/docs/rasa/custom-actions


from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SessionStarted, ActionExecuted, SlotSet
from datetime import datetime

class ActionSessionStart(Action):
    def name(self) -> Text:
        return "action_session_start"

    async def run(
        self, dispatcher: CollectingDispatcher, 
        tracker: Tracker, 
        domain: Dict[Text, Any]
    ) -> List[Dict[Text, Any]]:
        # Initialize events list with standard session start
        events = []
        
        # Standard behavior from default action_session_start
        events.append(SessionStarted())
        events.append(ActionExecuted("action_listen"))
        
        # Get current time
        current_time = datetime.now().timestamp()
        
        # Cek metadata sesi sebelumnya jika ada
        metadata = tracker.get_slot("session_metadata")
        
        if metadata and "last_active" in metadata:
            last_active = metadata.get("last_active")
            # Hitung berapa lama tidak aktif (dalam menit)
            inactive_time = (current_time - last_active) / 60
            
            # Jika tidak aktif lebih dari 10 menit, kirim pesan sesi berakhir
            if inactive_time >= 10:
                dispatcher.utter_message(template="utter_session_expired")
        
        # Update metadata sesi dengan waktu saat ini
        new_metadata = {"last_active": current_time}
        events.append(SlotSet("session_metadata", new_metadata))
        
        return events