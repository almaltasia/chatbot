# This files contains your custom actions which can be used to run
# custom Python code.
#
# See this guide on how to implement these action:
# https://rasa.com/docs/rasa/custom-actions


from typing import Any, Text, Dict, List
from rasa_sdk import Action, Tracker
from rasa_sdk.executor import CollectingDispatcher
from rasa_sdk.events import SessionStarted, ActionExecuted, SlotSet, ActiveLoop, AllSlotsReset
from datetime import datetime
import psycopg2
import logging

# Setup logger
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database connection parameters
DB_CONFIG = {
    "dbname":"db_ppks",
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

class ActionSubmitReport(Action):
    """Action untuk memvalidasi dan menyimpan laporan kasus ke database"""

    def name(self) -> Text:
        return "action_submit_report"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        # Ambil semua data dari slots
        reporter_type = tracker.get_slot("reporter_type")
        reporter_name = tracker.get_slot("reporter_name")
        prodi = tracker.get_slot("prodi")
        class_info = tracker.get_slot("class")
        gender = tracker.get_slot("gender")
        phone_number = tracker.get_slot("phone_number")
        address = tracker.get_slot("address")
        email = tracker.get_slot("email")
        violence_type = tracker.get_slot("violence_type")
        chronology = tracker.get_slot("chronology")
        disability = tracker.get_slot("disability")
        reported_status = tracker.get_slot("reported_status")
        report_reasons = tracker.get_slot("report_reasons")
        other_reason = tracker.get_slot("other_reason")
        other_contact = tracker.get_slot("other_contact")
        
        # Generate nomor referensi unik
        reference_number = self.generate_reference_number()
        
        try:
            # Buat koneksi ke database
            conn = get_db_connection()
            
            # Buat cursor untuk eksekusi query
            cur = conn.cursor()
            
            # 1. Dapatkan id untuk kategori pelapor
            cur.execute("SELECT id FROM kategori_pelapor WHERE nama = %s", (reporter_type,))
            kategori_pelapor_id = cur.fetchone()
            
            if not kategori_pelapor_id:
                # Handle jika kategori tidak ditemukan
                logger.warning(f"Kategori pelapor {reporter_type} tidak ditemukan di database")
                kategori_pelapor_id = None
            else:
                kategori_pelapor_id = kategori_pelapor_id[0]
            
            # 2. Dapatkan id untuk jenis kekerasan
            cur.execute("SELECT id FROM jenis_kekerasan WHERE nama = %s", (violence_type,))
            jenis_kekerasan_id = cur.fetchone()
            
            if not jenis_kekerasan_id:
                # Handle jika jenis kekerasan tidak ditemukan
                logger.warning(f"Jenis kekerasan {violence_type} tidak ditemukan di database")
                jenis_kekerasan_id = None
            else:
                jenis_kekerasan_id = jenis_kekerasan_id[0]
            
            # 3. Dapatkan id untuk status terlapor
            cur.execute("SELECT id FROM status_terlapor WHERE nama = %s", (reported_status,))
            status_terlapor_id = cur.fetchone()
            
            if not status_terlapor_id:
                # Handle jika status terlapor tidak ditemukan
                logger.warning(f"Status terlapor {reported_status} tidak ditemukan di database")
                status_terlapor_id = None
            else:
                status_terlapor_id = status_terlapor_id[0]
            # 4. Proses informasi disabilitas
            is_disabilitas = False
            jenis_disabilitas = None
            
            if disability and disability.lower() not in ["tidak", "tidak ada", "nggak", "nggak ada"]:
                is_disabilitas = True
                if disability.lower() == "ya":
                    # Jika hanya "Ya" tanpa detail, ambil dari slot yang terpisah jika ada
                    jenis_disabilitas = "Tidak disebutkan"
                else:
                    # Jika ada detail langsung di slot disability
                    jenis_disabilitas = disability
            
            # 5. Insert data ke tabel laporan_kasus - tanpa nomor referensi
            # Trigger database akan membuat nomor referensi otomatis
            cur.execute("""
                INSERT INTO laporan_kasus (
                    kategori_pelapor_id, nama_pelapor, program_studi,
                    kelas, jenis_kelamin, nomor_telepon, alamat, email,
                    is_disabilitas, jenis_disabilitas, jenis_kekerasan_id,
                    deskripsi_kejadian, status_terlapor_id, kontak_konfirmasi
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s
                ) RETURNING id, nomor_referensi
            """, (
                kategori_pelapor_id, reporter_name, prodi,
                class_info, gender, phone_number, address, email,
                is_disabilitas, jenis_disabilitas, jenis_kekerasan_id,
                chronology, status_terlapor_id, other_contact
            ))
            
            # Dapatkan ID laporan dan nomor referensi yang baru saja dibuat
            result = cur.fetchone()
            laporan_id = result[0]
            reference_number = result[1]
            
            # Proses alasan pengaduan seperti sebelumnya...
            # [kode untuk menyimpan alasan pengaduan]
            
            # Success message
            logger.info(f"Laporan berhasil disimpan dengan nomor referensi: {reference_number}")
            
        except Exception as e:
            # Log error jika terjadi kesalahan
            logger.error(f"Error saat menyimpan laporan: {str(e)}")
            dispatcher.utter_message(text="Maaf, terjadi kesalahan saat menyimpan laporan. Tim teknis kami akan segera menangani masalah ini.")
            return [SlotSet("reference_number", "ERROR")]
        
        finally:
            # Tutup cursor
            if 'cur' in locals():
                cur.close()
        
        # Return events dan set reference_number slot
        return [SlotSet("reference_number", reference_number)]
            
class ActionCancelReport(Action):
    """Action untuk membatalkan proses pelaporan dan mereset semua slot"""

    def name(self) -> Text:
        return "action_cancel_report"

    def run(self, dispatcher: CollectingDispatcher,
            tracker: Tracker,
            domain: Dict[Text, Any]) -> List[Dict[Text, Any]]:
        
        # Log pembatalan (opsional)
        logger.info(f"Proses pelaporan dibatalkan oleh pengguna: {tracker.sender_id}")
        
        # Reset semua slot pelaporan
        return [
            ActiveLoop(None),  # Deaktivasi form yang sedang aktif
            AllSlotsReset()  # Reset semua slot sekaligus
        ]