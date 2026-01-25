import SwiftUI
import MessageUI

struct MailData: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let attachmentData: Data?
}

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let attachmentData: Data?
    let onDismiss: (MFMailComposeResult) -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        LoggerService.shared.info(module: "MailComposeView", message: "开始创建邮件编辑器")
        LoggerService.shared.info(module: "MailComposeView", message: "附件数据: \(attachmentData?.count ?? 0) 字节")
        
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["jinch2287@gmail.com"])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        
        if let attachmentData = attachmentData {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "eAIPPad_logs_\(timestamp).txt"
            
            LoggerService.shared.info(module: "MailComposeView", message: "准备添加附件：\(filename)，大小：\(attachmentData.count) 字节")
            
            composer.addAttachmentData(
                attachmentData,
                mimeType: "text/plain",
                fileName: filename
            )
            
            LoggerService.shared.info(module: "MailComposeView", message: "✓ 已成功添加日志附件：\(filename)")
        } else {
            LoggerService.shared.warning(module: "MailComposeView", message: "⚠️ attachmentData 为 nil，未添加附件")
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: (MFMailComposeResult) -> Void
        
        init(onDismiss: @escaping (MFMailComposeResult) -> Void) {
            self.onDismiss = onDismiss
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                LoggerService.shared.error(module: "MailComposeView", message: "邮件发送错误：\(error.localizedDescription)")
            }
            
            switch result {
            case .sent:
                LoggerService.shared.info(module: "MailComposeView", message: "邮件已发送")
            case .saved:
                LoggerService.shared.info(module: "MailComposeView", message: "邮件已保存为草稿")
            case .cancelled:
                LoggerService.shared.info(module: "MailComposeView", message: "用户取消发送邮件")
            case .failed:
                LoggerService.shared.error(module: "MailComposeView", message: "邮件发送失败")
            @unknown default:
                LoggerService.shared.warning(module: "MailComposeView", message: "未知的邮件发送结果")
            }
            
            controller.dismiss(animated: true) {
                self.onDismiss(result)
            }
        }
    }
}
