//
//  SelectFiles.swift
//  Frotz
//
//  Created by Craig Smith on 5/12/23.
//

import Foundation
import UIKit

@objc
class FileCell: UITableViewCell {
    @IBOutlet weak var checkBox: CheckBox!
    @IBOutlet weak var fileLabel: UITextField!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

@objc
class CheckBox: UIButton {
    static var checkedImage : UIImage? = {
        if #available(iOS 13.0, *) {
            return  UIImage(systemName: "square.and.arrow.down.fill")
        }
        return UIImage(named: "square.and.arrow.down.fill")
    }()
    static var uncheckedImage : UIImage? = {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: "square")
        }
        return UIImage(named: "square")
    }()

    var isChecked = false {
        didSet {
            let image = isChecked ? CheckBox.checkedImage : CheckBox.uncheckedImage
            setImage(image, for: UIControl.State.normal)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(CheckBox.uncheckedImage, for: UIControl.State.normal)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder:aDecoder)
        addTarget(self, action: #selector(checkBoxTapped), for: UIControl.Event.touchUpInside)
        setTitle("", for: .normal)
    }
    @objc @IBAction func checkBoxTapped() {
        isChecked = !isChecked
    }
}

class SelFilesInstructionsHeader : UITableViewHeaderFooterView {
    let instructions = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        instructions.font = UIFont.systemFont(ofSize: 14)
        instructions.adjustsFontSizeToFitWidth = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureContents() {
        instructions.translatesAutoresizingMaskIntoConstraints = false
        instructions.numberOfLines = 0 //allow multiple lines
        contentView.addSubview(instructions)

        let myContraints = [
            instructions.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),

            // Center the label vertically, and use it to fill the remaining space in the header view.
            instructions.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            instructions.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            instructions.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ]
        myContraints.last?.priority = .required
        NSLayoutConstraint.activate(myContraints)
    }

}

@objc
public class SelectFilesViewController: UITableViewController {
    var prompt: String?
    var fileList: [String] = []
    var selectedFiles: [String] = []
    var doneHandler : ((_ files: [String]) -> Void)?
    var canceledHandler : (()->Void)?
    var instructions : String?
    var headerHeight : CGFloat = 0

    @objc(setTitle:files:doneHandler:canceledHandler:)
    public func set(title: String, files: [String], doneHandler: (([String])->Void)?, canceledHandler: (()->Void)?) {
        self.prompt = title
        self.doneHandler = doneHandler
        self.canceledHandler = canceledHandler
        fileList = files
    }
    @objc
    public func setInstructions(_ inst: String) {
        self.instructions = inst
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.title = prompt

        tableView.register(SelFilesInstructionsHeader.self,
              forHeaderFooterViewReuseIdentifier: "sectionHeader")

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
        self.navigationItem.leftBarButtonItem = cancelButton
        self.navigationItem.rightBarButtonItem = doneButton

    }
    @objc func cancelButtonTapped() {
        self.dismiss(animated: true, completion: nil)
        self.canceledHandler?()
    }

    @objc func doneButtonTapped() {
        self.dismiss(animated: true, completion: nil)
        self.doneHandler?(self.selectedFiles)
    }

    public override func tableView(_ tableView: UITableView,
            viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier:
                   "sectionHeader") as! SelFilesInstructionsHeader
        view.instructions.text = self.instructions
        view.configureContents()
        if (view.instructions.text != nil && headerHeight == 0) {
            headerHeight = view.contentView.subviews[0].frame.size.height
            tableView.reloadData()
        }
        return view
    }

    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return self.instructions != nil && headerHeight > 0 ? headerHeight : 100
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return fileList.count
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FileCell", for: indexPath) as! FileCell
        let isChecked = selectedFiles.contains(fileList[indexPath.row])
        cell.fileLabel.text = fileList[indexPath.row]
        cell.checkBox.isChecked = isChecked
        cell.checkBox.tag = indexPath.row
        cell.checkBox.addTarget(self, action: #selector(checkBoxValueChanged(_:)), for: .touchUpInside)
        return cell
    }

    @objc public func checkAllMatches(_ match: String) {
        for file in fileList {
            if let _ = file.range(of: match, options: .caseInsensitive) {
                if (!selectedFiles.contains(file)) {
                    selectedFiles.append(file)
                }
            }
        }
    }

    @objc @IBAction func checkBoxValueChanged(_ sender: CheckBox) {
        let rowIndex = sender.tag
        let fileName = fileList[rowIndex]
        if sender.isChecked {
            selectedFiles.append(fileName)
        } else {
            selectedFiles.removeAll(where: { $0 == fileName })
        }
    }
}
