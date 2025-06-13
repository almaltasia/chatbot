# This files contains your custom actions which can be used to run
# custom Python code.
#
# See this guide on how to implement these action:
# https://rasa.com/docs/rasa/custom-actions


from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker, FormValidationAction
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SessionStarted, ActionExecuted, SlotSet, ActiveLoop, AllSlotsReset, FollowupAction
from rasa_sdk.forms import ValidationAction
from rasa_sdk.types import DomainDict
from datetime import datetime
import psycopg2
import logging
import re

# Setup logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connection parameters
DB_CONFIG = {
    "dbname":"db_ppks_test",
    "user":"postgres",
    "password":"123",
    "host":"localhost",
    "port":"5432"
}
db_connection = None

def get_db_connection():
    global db_connection
    try:
        if db_connection is None or db_connection.closed:
            db_connection = psycopg2.connect(**DB_CONFIG)
            db_connection.autocommit = True
            logger.info("created new database connection")
    except psycopg2.Error as e:
        logger.error(f"Database connection error: {e}")
        raise
    return db_connection

# class ActionSessionStart(Action):
#     def name(self) -> Text:
#         return "action_session_start"

#     async def run(
#         self, dispatcher: CollectingDispatcher, 
#         tracker: Tracker, 
#         domain: Dict[Text, Any]
#     ) -> List[Dict[Text, Any]]:
#         # Initialize events list with standard session start
#         events = []
        
#         # Standard behavior from default action_session_start
#         events.append(SessionStarted())
#         events.append(ActionExecuted("action_listen"))
        
#         # Get current time
#         current_time = datetime.now().timestamp()
        
#         # Cek metadata sesi sebelumnya jika ada
#         metadata = tracker.get_slot("session_metadata")
        
#         if metadata and "last_active" in metadata:
#             last_active = metadata.get("last_active")
#             # Hitung berapa lama tidak aktif (dalam menit)
#             inactive_time = (current_time - last_active) / 60
            
#             # Jika tidak aktif lebih dari 10 menit, kirim pesan sesi berakhir
#             if inactive_time >= 10:
#                 dispatcher.utter_message(template="utter_session_expired")
        
#         # Update metadata sesi dengan waktu saat ini
#         new_metadata = {"last_active": current_time}
#         events.append(SlotSet("session_metadata", new_metadata))
        
#         return events

# Mapping untuk alasan pengaduan korban
REASON_MAPPING_KORBAN = {
    "1": "Butuh bantuan pemulihan",
    "2": "Ingin pelaku dihukum",
    "3": "Ingin perlindungan",
    "4": "Mencegah korban lain",
    "5": "Alasan lain"
}

# Mapping untuk alasan pengaduan saksi
REASON_MAPPING_SAKSI = {
    "1": "Khawatir dengan keadaan korban",
    "2": "Ingin pelaku ditindak tegas",
    "3": "Ingin kampus lebih aman",
    "4": "Ingin korban dilindungi",
    "5": "Alasan lain"
}

class ActionHandleConfirmation(Action):
    def name(self) -> Text:
        return "action_handle_confirmation"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        active_loop = tracker.active_loop.get('name')
        form_status = tracker.get_slot('requested_slot')
        
        # Log for debugging
        logger.info(f"Handling confirmation: active_loop={active_loop}, form_status={form_status}")
        
        # Only process if we're in the right state (form completed, waiting for final confirmation)
        if active_loop is None and form_status is None:
            logger.info("Confirmation acknowledged, proceeding to submit report")
            return []
        else:
            logger.warning(f"action_handle_confirmation called in unexpected state: active_loop={active_loop}, form_status={form_status}")
            return []
        
class ValidateReportForm(FormValidationAction):
    def name(self) -> Text:
        return "validate_report_form"

    def validate_reporter_type(
        self,
        slot_value: Any,
        dispatcher: CollectingDispatcher,
        tracker: Tracker,
        domain: DomainDict,
    ) -> Dict[Text, Any]:
        value = slot_value.lower() if isinstance(slot_value, str) else ""
        
        if "korban" in value:
            logger.info(f"Validated reporter_type as korban")
            return {"reporter_type": "korban"}
        elif "saksi" in value:
            logger.info(f"Validated reporter_type as saksi")
            return {"reporter_type": "saksi"}
        else:
            dispatcher.utter_message(text="Mohon tentukan apakah Anda sebagai korban atau saksi dengan mengetik 'KORBAN' atau 'SAKSI'.")
            logger.warning(f"Invalid reporter_type value: {value}")
            return {"reporter_type": None}
    
    def validate_identity_data(
        self,
        slot_value: Any,
        dispatcher: CollectingDispatcher,
        tracker: Tracker,
        domain: DomainDict,
    ) -> Dict[Text, Any]:
        try:
            extracted_data = self._extract_identity_data(slot_value)
            logger.info(f"Extracted identity data: {extracted_data}")
            
            # Validasi field penting
            required_fields = ["reporter_name", "phone_number"]
            missing_fields = [field for field in required_fields if not extracted_data.get(field)]
            
            if missing_fields:
                missing_field_names = ", ".join(missing_fields).replace("reporter_name", "Nama").replace("phone_number", "Nomor Telepon")
                dispatcher.utter_message(text=f"Beberapa informasi penting tidak terisi dengan lengkap: {missing_field_names}. Mohon isi kembali form identitas.")
                logger.warning(f"Missing required fields in identity data: {missing_fields}")
                return {"identity_data": None}
            result = {
                "identity_data": slot_value,
                **extracted_data
            }
            
            logger.info(f"Identity data validated successfully")
            return result
            
        except Exception as e:
            logger.error(f"Error validating identity data: {str(e)}")
            dispatcher.utter_message(text="Terjadi kesalahan saat memproses data identitas. Mohon coba lagi.")
            return {"identity_data": None}
    
    def validate_incident_data(
        self,
        slot_value: Any,
        dispatcher: CollectingDispatcher,
        tracker: Tracker,
        domain: DomainDict,
    ) -> Dict[Text, Any]:
        try:
            logger.info(f"Validating incident data: {slot_value}")

            # Parse incident form dengan regex
            extracted_data = self._extract_incident_data(slot_value)
            logger.info(f"Extracted incident data: {extracted_data}")

            required_fields = ["violence_type", "chronology"]
            missing_fields = [field for field in required_fields if not extracted_data.get(field)]

            if missing_fields:
                missing_field_names = ", ".join(missing_fields).replace("violence_type", "Jenis Kekerasan").replace("chronology", "Kronologi")
                dispatcher.utter_message(text=f"Beberapa informasi penting tidak terisi dengan lengkap: {missing_field_names}. Mohon isi kembali form kejadian.")
                logger.warning(f"Missing required fields in incident data: {missing_fields}")
                return {"incident_data": None}

            result = {
                "incident_data": slot_value,
                "violence_type": extracted_data.get("violence_type"),
                "chronology": extracted_data.get("chronology"),
                "reported_status": extracted_data.get("reported_status")
            }

            logger.info(f"Incident data validated successfully: {result}")
            return result
        
        except Exception as e:
            logger.error(f"Error validating incident data: {str(e)}", exc_info=True)
            dispatcher.utter_message(text="Terjadi kesalahan saat memproses data kejadian. Mohon coba lagi.")
            return {"incident_data": None}
    
    def validate_support_data(
        self,
        slot_value: Any,
        dispatcher: CollectingDispatcher,
        tracker: Tracker,
        domain: DomainDict,
    ) -> Dict[Text, Any]:
        try:
            logger.info(f"Validating support data: {slot_value}")
            
            extracted_data = self._extract_support_data(slot_value)
            logger.info(f"Extracted support data: {extracted_data}")
            
            if not extracted_data.get("report_reasons_numbers") and not extracted_data.get("other_reason"):
                dispatcher.utter_message(text="Mohon tentukan alasan pengaduan Anda dengan memilih nomor pilihan (1-5) atau berikan alasan lain secara langsung. Mohon isi kembali form.")
                logger.warning(f"Missing required report reasons")
                return {"support_data": None}
            
            # Konversi nomor alasan ke teks berdasarkan jenis pelapor
            reporter_type = tracker.get_slot("reporter_type")
            reason_mapping = REASON_MAPPING_KORBAN if reporter_type.lower() == "korban" else REASON_MAPPING_SAKSI
            
            reason_numbers = extracted_data.get("report_reasons_numbers", [])
            reason_texts = []
            for num in reason_numbers:
                if num in reason_mapping:
                    reason_texts.append(reason_mapping[num])
            
            formatted_reasons = ", ".join(reason_texts)
            
            # Tambahkan alasan lain jika ada
            other_reason = extracted_data.get("other_reason")
            if "5" in reason_numbers and other_reason:
                if formatted_reasons:
                    formatted_reasons += f"; Alasan lain: {other_reason}"
                else:
                    formatted_reasons = f"Alasan lain: {other_reason}"
            elif not reason_numbers and other_reason:
                formatted_reasons = f"Alasan lain: {other_reason}"
            
            if not formatted_reasons:
                formatted_reasons = "Tidak disebutkan"
            
            other_contact = extracted_data.get("other_contact", "Tidak ada")
            
            result = {
                "support_data": slot_value,
                "report_reasons": formatted_reasons,
                "other_reason": other_reason,
                "other_contact": other_contact
            }
            
            logger.info(f"Support data validated successfully: {result}")
            return result
            
        except Exception as e:
            logger.error(f"Error validating support data: {str(e)}", exc_info=True)
            dispatcher.utter_message(text="Terjadi kesalahan saat memproses data pendukung. Mohon coba lagi.")
            return {"support_data": None}
    
    def _extract_identity_data(self, text: str) -> Dict[str, Any]:
        extracted_data = {}
        
        patterns = {
            "reporter_name": r'(?:1\.|Nama\s+Lengkap)[^:]*:\s*([^\n]+?)(?=\s*(?:2\.|Program\s+Studi)|$)',
            "prodi": r'(?:2\.|Program\s+Studi)[^:]*:\s*([^\n]+?)(?=\s*(?:3\.|Kelas)|$)',
            "class": r'(?:3\.|Kelas)[^:]*:\s*([^\n]+?)(?=\s*(?:4\.|Jenis\s+Kelamin)|$)',
            "gender": r'(?:4\.|Jenis\s+Kelamin)[^:]*:\s*([^\n]+?)(?=\s*(?:5\.|Nomor\s+Telepon)|$)',
            "phone_number": r'(?:5\.|Nomor\s+Telepon|Nomor\s+Telepon/WA|No\.?\s*(?:Telp|HP|Telepon))[^:]*:\s*([0-9+\-\s]+)(?=\s*(?:6\.|Alamat)|$)',
            "address": r'(?:6\.|Alamat)[^:]*:\s*([^\n]+?)(?=\s*(?:7\.|Email)|$)',
            "email": r'(?:7\.|Email)[^:]*:\s*([^\n]+?)(?=\s*(?:8\.|Apakah|Disabilitas)|$)',
            "disability": r'(?:8\.|(?:Apakah\s+)?(?:Memiliki\s+)?Disabilitas)[^:]*:\s*([^\n]+)',
        }
        
        for field, pattern in patterns.items():
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                value = match.group(1).strip()
                if field == "phone_number":
                    value = re.sub(r'[^\d+]', '', value)
                extracted_data[field] = value if value else None
        
        return extracted_data
    
    def _extract_incident_data(self, text: str) -> Dict[str, Any]:
        extracted_data = {}
        
        logger.info(f"Extracting incident data from: {text}")
        
        violence_type_pattern = r'(?:Jenis\s+Kekerasan)[^:]*:\s*([^\n]+)'
        violence_match = re.search(violence_type_pattern, text, re.IGNORECASE)
        if violence_match:
            violence_type = violence_match.group(1).strip()
            extracted_data["violence_type"] = violence_type
            logger.info(f"Extracted violence_type: {violence_type}")
        else:
            logger.warning("Failed to extract violence_type")
        
        chronology_pattern = r'(?:Kronologi)[^:]*:\s*([\s\S]*?)(?=(?:Status\s+(?:Terlapor|Pelaku)|={3,})|$)'
        chronology_match = re.search(chronology_pattern, text, re.IGNORECASE)
        if chronology_match:
            chronology = chronology_match.group(1).strip()
            extracted_data["chronology"] = chronology
            logger.info(f"Extracted chronology: {chronology}")
        else:
            logger.warning("Failed to extract chronology")
        
        status_pattern = r'(?:Status\s+(?:Terlapor|Pelaku))[^:]*:\s*([^\n=]+)'
        status_match = re.search(status_pattern, text, re.IGNORECASE)
        if status_match:
            reported_status = status_match.group(1).strip()
            extracted_data["reported_status"] = reported_status
            logger.info(f"Extracted reported_status: {reported_status}")
        else:
            logger.warning("Failed to extract reported_status")
        
        return extracted_data
    
    def _extract_support_data(self, text: str) -> Dict[str, Any]:
        extracted_data = {}

        logger.info(f"Extracting support data from: {text}")

        reason_patterns = [
            r'(?:Alasan\s*(?:Melapor|Pengaduan))[^:]*:\s*([\d,\s dan]+)',
            r'(?:Alasan)[^:]*:\s*([\d,\s dan]+)',
        ]

        reason_numbers = []
        for pattern in reason_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                reasons_text = match.group(1).strip()
                logger.info(f"Found reason text: {reasons_text}")
                reason_numbers = re.findall(r'\d+', reasons_text)
                if reason_numbers:
                    extracted_data["report_reasons_numbers"] = reason_numbers
                    logger.info(f"Extracted reason numbers: {reason_numbers}")
                    break
                
        other_reason_pattern = r'(?:Alasan\s+lain)[^:]*:\s*([^\n]+)'
        other_reason_match = re.search(other_reason_pattern, text, re.IGNORECASE)
        if other_reason_match:
            other_reason = other_reason_match.group(1).strip()
            if other_reason and other_reason.lower() not in ["tidak ada", "tidak", "-", "0"]:
                extracted_data["other_reason"] = other_reason
                logger.info(f"Extracted other reason: {other_reason}")

        contact_pattern = r'(?:Kontak\s+Lain)[^:]*:\s*([^\n=]+)'
        contact_match = re.search(contact_pattern, text, re.IGNORECASE)
        if contact_match:
            other_contact = contact_match.group(1).strip()
            if other_contact and other_contact.lower() not in ["tidak ada", "tidak", "-", "0"]:
                extracted_data["other_contact"] = other_contact
                logger.info(f"Extracted other contact: {other_contact}")

        return extracted_data

class ActionSubmitReport(Action):
    def name(self) -> Text:
        return "action_submit_report"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        reporter_type = tracker.get_slot("reporter_type")
        if reporter_type:
            reporter_type = reporter_type.lower()
        reporter_name = tracker.get_slot("reporter_name")
        prodi = tracker.get_slot("prodi")
        class_info = tracker.get_slot("class")
        gender = tracker.get_slot("gender")
        phone_number = tracker.get_slot("phone_number")
        address = tracker.get_slot("address")
        email = tracker.get_slot("email")
        disability = tracker.get_slot("disability")
        violence_type = tracker.get_slot("violence_type")
        chronology = tracker.get_slot("chronology")
        reported_status = tracker.get_slot("reported_status")
        if reported_status:
            reported_status = reported_status.lower()
        report_reasons = tracker.get_slot("report_reasons")
        other_contact = tracker.get_slot("other_contact")
        
        logger.info(f"Submitting report for {reporter_name} as {reporter_type}")
        
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            # 1. Get id for reporter category
            cur.execute("SELECT id_kategori_pelapor FROM kategori_pelapor WHERE kategori = %s", (reporter_type,))
            kategori_pelapor_id = cur.fetchone()
            
            if not kategori_pelapor_id:
                # Handle case where category is not found
                logger.warning(f"Reporter category {reporter_type} not found in database")
                kategori_pelapor_id = None
            else:
                kategori_pelapor_id = kategori_pelapor_id[0]
            
            # 2. Get id for reported status
            cur.execute("SELECT id_status FROM status WHERE status = %s", (reported_status,))
            status_terlapor_id = cur.fetchone()
            
            if not status_terlapor_id:
                # Handle case where reported status is not found
                logger.warning(f"Reported status {reported_status} not found in database")
                status_terlapor_id = None
            else:
                status_terlapor_id = status_terlapor_id[0]
            
            # 3. Process disability information
            is_disabilitas = False
            jenis_disabilitas = None
            
            if disability and disability.lower() not in ["tidak", "tidak ada", "nggak", "nggak ada"]:
                is_disabilitas = True
                if disability.lower() == "ya":
                    jenis_disabilitas = "Tidak disebutkan"
                else:
                    jenis_disabilitas = disability
            
            # 4. Insert data into laporan_kasus table
            # The trigger in database will automatically generate nomor_referensi
            cur.execute("""
                INSERT INTO laporan_kasus (
                    kategori_pelapor_id, nama_pelapor, program_studi,
                    kelas, jenis_kelamin, nomor_telepon, alamat, email,
                    is_disabilitas, jenis_disabilitas, jenis_kekerasan,
                    deskripsi_kejadian, status_terlapor_id, alasan_lapor, kontak_lain
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                ) RETURNING id_laporan, nomor_referensi
            """, (
                kategori_pelapor_id, reporter_name, prodi,
                class_info, gender, phone_number, address, email,
                is_disabilitas, jenis_disabilitas, violence_type,
                chronology, status_terlapor_id, report_reasons, other_contact
            ))
            
            # Get the report ID and reference number that was just created
            result = cur.fetchone()
            laporan_id = result[0]
            reference_number = result[1]
            
            logger.info(f"Report successfully saved with reference number: {reference_number}")
            
            cur.close()
            
        except Exception as e:
            logger.error(f"Error when saving report: {str(e)}")
            dispatcher.utter_message(text="Maaf, terjadi kesalahan saat menyimpan laporan. Tim teknis kami akan segera menangani masalah ini.")
            return [SlotSet("reference_number", "ERROR")]
        
        return [SlotSet("reference_number", reference_number),
            SlotSet("reporter_type", None),
            SlotSet("identity_data", None),
            SlotSet("reporter_name", None),
            SlotSet("prodi", None),
            SlotSet("class", None),
            SlotSet("gender", None),
            SlotSet("phone_number", None),
            SlotSet("address", None),
            SlotSet("email", None),
            SlotSet("disability", None),
            SlotSet("incident_data", None),
            SlotSet("violence_type", None),
            SlotSet("chronology", None),
            SlotSet("reported_status", None),
            SlotSet("support_data", None),
            SlotSet("report_reasons", None),
            SlotSet("other_reason", None),
            SlotSet("other_contact", None)
        ]
    
class ActionCancelReport(Action):
    def name(self) -> Text:
        return "action_cancel_report"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        logger.info(f"Proses pelaporan dibatalkan oleh pengguna: {tracker.sender_id}")
        
        dispatcher.utter_message(response="utter_report_cancelled")
        
        return [
            ActiveLoop(None),
            AllSlotsReset()
        ]
class ActionResetReportSlots(Action):
    def name(self) -> Text:
        return "action_reset_report_slots"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        logger.info(f"Resetting all report slots for user: {tracker.sender_id}")
        
        return [
            SlotSet("reporter_type", None),
            SlotSet("identity_data", None),
            SlotSet("reporter_name", None),
            SlotSet("prodi", None),
            SlotSet("class", None),
            SlotSet("gender", None),
            SlotSet("phone_number", None),
            SlotSet("address", None),
            SlotSet("email", None),
            SlotSet("disability", None),
            SlotSet("incident_data", None),
            SlotSet("violence_type", None),
            SlotSet("chronology", None),
            SlotSet("reported_status", None),
            SlotSet("support_data", None),
            SlotSet("report_reasons", None),
            SlotSet("other_reason", None),
            SlotSet("other_contact", None),
            SlotSet("reference_number", None)
        ]

class ActionShowConfirmation(Action):
    def name(self) -> Text:
        return "action_show_confirmation"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        # Mengambil semua data dari slot
        reporter_type = tracker.get_slot("reporter_type") or "Tidak diketahui"
        reporter_name = tracker.get_slot("reporter_name") or "Tidak diketahui"
        prodi = tracker.get_slot("prodi") or "Tidak diketahui"
        class_info = tracker.get_slot("class") or "Tidak diketahui"
        gender = tracker.get_slot("gender") or "Tidak diketahui"
        phone_number = tracker.get_slot("phone_number") or "Tidak diketahui"
        address = tracker.get_slot("address") or "Tidak diketahui"
        email = tracker.get_slot("email") or "Tidak diketahui"
        disability = tracker.get_slot("disability") or "Tidak"
        violence_type = tracker.get_slot("violence_type") or "Tidak diketahui"
        chronology = tracker.get_slot("chronology") or "Tidak diketahui"
        reported_status = tracker.get_slot("reported_status") or "Tidak diketahui"
        report_reasons = tracker.get_slot("report_reasons") or "Tidak diketahui"
        other_contact = tracker.get_slot("other_contact") or "Tidak ada"
        
        logger.info(f"Confirmation data: reporter_type={reporter_type}, name={reporter_name}, reasons={report_reasons}, contact={other_contact}")

        dispatcher.utter_message(response="utter_confirm_report", 
            reporter_type=reporter_type,
            reporter_name=reporter_name,
            prodi=prodi,
            class_info=class_info,
            gender=gender,
            phone_number=phone_number,
            email=email,
            address=address,
            disability=disability,
            violence_type=violence_type,
            reported_status=reported_status,
            chronology=chronology,
            report_reasons=report_reasons,
            other_contact=other_contact)

        return []
    
class ActionAnswerFAQ(Action):
    def name(self) -> Text:
        return "action_faq_response"
    
    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        user_message = tracker.latest_message.get('text', '')
        faq_topic = tracker.get_slot("faq_topic")
        
        try:
            logger.info(f"FAQ query - Message: '{user_message}', Topic entity: '{faq_topic}'")
            
            answer = self.get_faq_answer(user_message, faq_topic)
            
            if answer:
                dispatcher.utter_message(text=answer)
            else:
                dispatcher.utter_message(response="utter_faq_fallback")
        
        except Exception as e:
            logger.error(f"Error saat mencari jawaban FAQ: {str(e)}")
            dispatcher.utter_message(text="Maaf, terjadi kesalahan saat mencari informasi. "
                                            "Silakan coba lagi atau hubungi Satgas PPKPT PNUP secara langsung.")
        
        return []
    
    def get_faq_answer(self, user_message: Text, faq_topic: Text = None) -> Text:
        conn = None
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            if faq_topic:
                logger.info(f"Searching by entity: '{faq_topic}'")
                
                query = """
                    SELECT judul, deskripsi
                    FROM materi
                    WHERE judul ILIKE %s 
                        OR phrases::text ILIKE %s
                    LIMIT 1
                """
                
                search_pattern = f"%{faq_topic}%"
                cur.execute(query, (search_pattern, search_pattern))
                
                result = cur.fetchone()
                
                if result:
                    judul, deskripsi = result
                    
                    # 🎯 GUNAKAN CONSISTENT FORMATTING
                    format_type = self.get_answer_format_type(judul)
                    answer = self.format_answer_by_type(judul, deskripsi, format_type)
                    
                    logger.info(f"Found answer with format: {format_type}")
                    return answer
                else:
                    # Jika tidak ditemukan berdasarkan entity, coba cari berdasarkan pesan pengguna
                    logger.info("Entity search yielded no results, falling back to message search")
            
            # Fallback: cari berdasarkan kata kunci dalam pesan pengguna
            cleaned_message = self.clean_message(user_message)
            keywords = cleaned_message.split()
            
            if not keywords:
                return None
            
            logger.info(f"Searching by cleaned message keywords: {keywords}")
            
            conditions = []
            params = []
            
            for keyword in keywords:
                if len(keyword) > 3:
                    conditions.append("(judul ILIKE %s OR deskripsi ILIKE %s OR phrases::text ILIKE %s)")
                    search_pattern = f"%{keyword}%"
                    params.extend([search_pattern, search_pattern, search_pattern])
            
            if not conditions:
                return None
            
            query = f"""
                SELECT judul, deskripsi, 
                        COUNT(*) as match_count
                FROM materi
                WHERE {" OR ".join(conditions)}
                GROUP BY judul, deskripsi
                ORDER BY match_count DESC
                LIMIT 1
            """
            
            cur.execute(query, params)
            result = cur.fetchone()
            
            if result:
                judul, deskripsi, _ = result
                
                format_type = self.get_answer_format_type(judul)
                answer = self.format_answer_by_type(judul, deskripsi, format_type)
                
                logger.info(f"Found answer with format: {format_type}")
                return answer
            
            return None
            
        except Exception as e:
            logger.error(f"Error dalam get_faq_answer: {str(e)}")
            raise
        
        finally:
            if conn:
                conn.close()
    
    def get_answer_format_type(self, judul: str) -> str:
        """Menentukan tipe format berdasarkan judul (Simple atau Permendikbud)"""
        
        judul_lower = judul.lower()
        
        simple_keywords = [
            'Struktur Satgas',
            'Permendikbudristek No.55/2024',
            'Layanan Pelaporan'
        ]
        
        # Check untuk simple format
        for simple_keyword in simple_keywords:
            if simple_keyword in judul_lower:
                return 'simple'
        
        # Default: Permendikbud untuk semua materi regulasi umum
        return 'permendikbud'
    
    def format_answer_by_type(self, judul: str, deskripsi: str, format_type: str) -> str:
        """Format jawaban sesuai tipe yang ditentukan (Simple atau Permendikbud)"""
        
        if format_type == 'simple':
            # Format simple tanpa embel-embel
            return f"*{judul}*\n\n{deskripsi}"
        
        elif format_type == 'permendikbud':
            # Format dengan Permendikbud
            return f"*{judul}*\n\nMenurut Permendikbudristek No. 55 Tahun 2025, {deskripsi}"
        
        else:
            # Fallback ke simple jika ada error
            return f"*{judul}*\n\n{deskripsi}"
    
    def clean_message(self, message: Text) -> Text:
        """Bersihkan pesan dari kata-kata yang tidak perlu"""
        message = re.sub(r'[^\w\s]', ' ', message.lower())
        stopwords = [
            'apa', 'yang', 'di', 'dan', 'itu', 'dengan', 'untuk', 'tidak', 'ini', 'dari',
            'dalam', 'akan', 'pada', 'juga', 'saya', 'ke', 'karena', 'secara', 'oleh',
            'tentang', 'seperti', 'dapat', 'bagaimana', 'kenapa', 'mengapa', 'siapa',
            'dimana', 'kapan', 'berikan', 'tolong', 'jelaskan', 'sih', 'dong', 'ya',
            'apakah', 'adalah', 'kok', 'gimana', 'caranya', 'cara', 'bisa', 'biar',
            'apa', 'dimaksud', 'maksud', 'arti', 'definisi', 'pengertian', 'jelaskan',
            'tentang', 'mohon', 'bisakah', 'bisa', 'dijelaskan', 'penjelasan'
        ]
        
        words = message.split()
        cleaned_words = [word for word in words if word.lower() not in stopwords and len(word) > 1]
        
        return ' '.join(cleaned_words)

class ActionListFAQTopics(Action):

    def name(self) -> Text:
        return "action_list_faq_topics"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        try:
            topics_by_category = self.get_categorized_topics()
            
            if topics_by_category:
                intro_message = "Berikut adalah informasi yang bisa saya bantu jelaskan tentang pencegahan dan penanganan kekerasan:"
                
                message_parts = [intro_message]
                
                for kategori, topics in topics_by_category.items():
                    message_parts.append(f"\n📚 *{kategori.upper()}*")
                    
                    for idx, topic in enumerate(topics, start=1):
                        capitalized_topic = self.capitalize_first_letter(topic)
                        message_parts.append(f"{idx}. {capitalized_topic}")
                
                usage_message = "\n💡 *Cara Menggunakan*\nUntuk mendapatkan informasi detail, Anda bisa menanyakan salah satu topik di atas. Contoh:\n- \"Apa itu kekerasan fisik?\"\n- \"Jelaskan tentang hak korban\"\n- \"Bagaimana prosedur pelaporan?\""
                
                message_parts.append(usage_message)
                
                full_message = "\n".join(message_parts)
                
                dispatcher.utter_message(text=full_message)
                
            else:
                dispatcher.utter_message(text="Mohon maaf, saat ini belum ada daftar informasi yang tersedia di database. Silakan hubungi Satgas PPKPT PNUP secara langsung di nomor 0812-xxxx-xxxx untuk informasi lebih lanjut.")
        
        except Exception as e:
            logger.error(f"Error saat mengambil daftar topik FAQ: {str(e)}")
            dispatcher.utter_message(text="Maaf, terjadi kesalahan saat mengambil daftar informasi. Silakan coba lagi atau hubungi Satgas PPKPT PNUP secara langsung di nomor 0812-xxxx-xxxx.")
        
        return []
    
    def capitalize_first_letter(self, text):
        if not text:
            return text
        return text[0].upper() + text[1:]
    
    def get_categorized_topics(self) -> Dict[str, List[str]]:
        
        kategori_urutan = [
        'umum', 
        'bentuk',  
        'pencegahan dan penanganan',
        'tata cara penanganan',
        'hak',
        'sanksi',
        'satgas',
        'lain-lain'
        ]
        conn = None
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            query = """
                SELECT k.kategori, m.judul
                FROM materi m
                JOIN kategori_materi k ON m.kategori_id = k.id_kategori_materi
                ORDER BY k.kategori, m.judul
            """
            
            cur.execute(query)
            
            results = cur.fetchall()
            
            categorized_topics = {}
            for kategori, judul in results:
                if kategori not in categorized_topics:
                    categorized_topics[kategori] = []
                categorized_topics[kategori].append(judul)
            
            sorted_topics = {}
            for kategori in kategori_urutan:
                if kategori in categorized_topics:
                    sorted_topics[kategori] = categorized_topics[kategori]
        
            return sorted_topics
            
        except Exception as e:
            logger.error(f"Error dalam get_categorized_topics: {str(e)}")
            raise
        
        finally:
            if conn:
                conn.close()

class ValidateTrackingForm(FormValidationAction):
    def name(self) -> Text:
        return "validate_tracking_form"

    def validate_tracked_reference_number(
        self,
        slot_value: Any,
        dispatcher: CollectingDispatcher,
        tracker: Tracker,
        domain: DomainDict,
    ) -> Dict[Text, Any]:
        if slot_value and isinstance(slot_value, str):
            # Clean input: remove spaces, convert to uppercase
            cleaned_value = slot_value.strip().upper()
            
            # Check if already in correct format PPKS-YYMMDDXXX
            pattern = r'^PPKS-\d{9}$'
            
            if re.match(pattern, cleaned_value):
                logger.info(f"Valid reference number: {cleaned_value}")
                return {"tracked_reference_number": cleaned_value}
            
            digit_only = re.search(r'\d{9}', cleaned_value)
            if digit_only:
                formatted_ref = f"PPKS-{digit_only.group()}"
                logger.info(f"Auto-formatted reference: {formatted_ref}")
                return {"tracked_reference_number": formatted_ref}
            
            # Jika format salah total
            dispatcher.utter_message(
                text="❌ Format nomor referensi tidak valid.\n\n"
                     "Silakan masukkan nomor dengan format: **PPKS-YYMMDDXXX**"
            )
            return {"tracked_reference_number": None}
        
        dispatcher.utter_message(
            text="🔍 Silakan masukkan nomor referensi laporan Anda.\n"
                 "Format: PPKS-YYMMDDXXX (contoh: PPKS-25051234)"
        )
        return {"tracked_reference_number": None}

class ActionTrackReport(Action):

    def name(self) -> Text:
        return "action_track_report"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        reference_number = tracker.get_slot("tracked_reference_number")
        
        if not reference_number:
            dispatcher.utter_message(text="Nomor referensi tidak ditemukan. Silakan coba lagi.")
            return []
        
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            query = """
                SELECT 
                    lr.nomor_referensi,
                    lr.status_laporan
                FROM laporan_kasus lr
                WHERE lr.nomor_referensi = %s AND lr.detele_at IS NULL
            """
            
            cur.execute(query, (reference_number,))
            result = cur.fetchone()
            
            if result:
                nomor_ref, status = result
                
                # Mapping status ke deskripsi
                status_descriptions = {
                    "Submitted": "Laporan telah diterima dan dalam antrian review",
                    "Under Review": "Sedang ditinjau oleh tim Satgas PPKPT",
                    "In Investigation": "Dalam proses investigasi",
                    "Follow-up Required": "Memerlukan tindak lanjut tambahan",
                    "Resolved": "Kasus telah diselesaikan",
                    "Closed": "Kasus telah ditutup"
                }
                
                status_description = status_descriptions.get(status, status)
                
                dispatcher.utter_message(
                    response="utter_track_report_found",
                    tracked_reference_number=nomor_ref,
                    status_description=status_description
                )
                
                logger.info(f"Successfully tracked report: {reference_number}")
                
            else:
                dispatcher.utter_message(
                    response="utter_track_report_not_found",
                    tracked_reference_number=reference_number
                )
                
                logger.warning(f"Report not found for reference: {reference_number}")
            
            cur.close()
            
        except Exception as e:
            logger.error(f"Error tracking report {reference_number}: {str(e)}")
            dispatcher.utter_message(
                response="utter_track_report_error"
            )
        
        return [
            SlotSet("tracked_reference_number", None)
        ]