import UIKit

/// Full-screen (within the keyboard) candidate browser.
///
/// A uniform five-across grid — the layout used by common Mandarin IMEs when
/// the candidate sheet is expanded. Every entry shares a cell; nothing gets a
/// private full-width row.
final class ExpandedCandidatesPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private static let columns = 5
    private static let rowHeight: CGFloat = 44
    private static let accent = UIColor(named: "AccentColor") ?? .systemIndigo

    var onSelect: ((Int) -> Void)?
    var onCollapse: (() -> Void)?
    var onDismissKeyboard: (() -> Void)?
    var onNextKeyboard: (() -> Void)?

    private var candidates: [RimeCandidate] = []
    private var highlightedIndex = 0

    private let collectionView: UICollectionView
    private let titleLabel = UILabel()
    private let collapseButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)
    private let globeButton = UIButton(type: .system)
    private let keyboardButton = UIButton(type: .system)

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reload(candidates: [RimeCandidate], highlightedIndex: Int) {
        self.candidates = candidates
        self.highlightedIndex = candidates.indices.contains(highlightedIndex) ? highlightedIndex : 0
        collectionView.reloadData()
        if !candidates.isEmpty {
            collectionView.scrollToItem(
                at: IndexPath(item: 0, section: 0),
                at: .top,
                animated: false
            )
        }
    }

    // MARK: - Layout

    private func configure() {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let handle = UIView()
        handle.backgroundColor = .tertiaryLabel
        handle.layer.cornerRadius = 2.5
        handle.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = MobileL10n.t(.candidatePanelTitle)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        var collapseConfig = UIButton.Configuration.plain()
        collapseConfig.image = UIImage(systemName: "chevron.down")
        collapseConfig.baseForegroundColor = Self.accent
        collapseButton.configuration = collapseConfig
        collapseButton.accessibilityLabel = MobileL10n.t(.candidateCollapse)
        collapseButton.addAction(UIAction { [weak self] _ in self?.onCollapse?() }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [UIView(), titleLabel, collapseButton])
        header.axis = .horizontal
        header.alignment = .center
        collapseButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        header.arrangedSubviews.first?
            .widthAnchor.constraint(equalToConstant: 44).isActive = true

        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(CandidateCell.self, forCellWithReuseIdentifier: CandidateCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        var globeConfig = UIButton.Configuration.plain()
        globeConfig.image = UIImage(systemName: "globe")
        globeConfig.baseForegroundColor = .label
        globeButton.configuration = globeConfig
        globeButton.accessibilityLabel = MobileL10n.t(.keySwitchKeyboard)
        globeButton.addAction(UIAction { [weak self] _ in self?.onNextKeyboard?() }, for: .touchUpInside)

        dismissButton.setTitle(MobileL10n.t(.candidateDismissKeyboard), for: .normal)
        dismissButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        dismissButton.setTitleColor(Self.accent, for: .normal)
        dismissButton.addAction(UIAction { [weak self] _ in self?.onDismissKeyboard?() }, for: .touchUpInside)

        var keyboardConfig = UIButton.Configuration.plain()
        keyboardConfig.image = UIImage(systemName: "keyboard")
        keyboardConfig.baseForegroundColor = .label
        keyboardButton.configuration = keyboardConfig
        keyboardButton.accessibilityLabel = MobileL10n.t(.candidateCollapse)
        keyboardButton.addAction(UIAction { [weak self] _ in self?.onCollapse?() }, for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [globeButton, dismissButton, keyboardButton])
        footer.axis = .horizontal
        footer.distribution = .equalCentering
        footer.alignment = .center
        globeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        keyboardButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let stack = UIStackView(arrangedSubviews: [handle, header, collectionView, footer])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(12, after: handle)
        addSubview(stack)

        NSLayoutConstraint.activate([
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),
            handle.centerXAnchor.constraint(equalTo: stack.centerXAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),

            header.heightAnchor.constraint(equalToConstant: 36),
            footer.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .absolute(rowHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(rowHeight)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            return section
        }
    }

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        candidates.isEmpty ? 0 : 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        candidates.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: CandidateCell.reuseID,
            for: indexPath
        ) as! CandidateCell
        let candidate = candidates[indexPath.item]
        cell.configure(
            text: candidate.text,
            selected: indexPath.item == highlightedIndex,
            showBottomRule: true,
            accent: Self.accent
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}

// MARK: - Cell

private final class CandidateCell: UICollectionViewCell {
    static let reuseID = "ExpandedCandidateCell"

    private let wordLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wordLabel.font = .preferredFont(forTextStyle: .body)
        wordLabel.textColor = .label
        wordLabel.textAlignment = .center
        wordLabel.adjustsFontSizeToFitWidth = true
        wordLabel.minimumScaleFactor = 0.6
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(wordLabel)

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            wordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            wordLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            wordLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, selected: Bool, showBottomRule: Bool, accent: UIColor) {
        wordLabel.text = text
        wordLabel.textColor = selected ? accent : .label
        wordLabel.font = selected
            ? .preferredFont(forTextStyle: .headline)
            : .preferredFont(forTextStyle: .body)
        contentView.backgroundColor = selected ? accent.withAlphaComponent(0.12) : .clear
        separator.isHidden = !showBottomRule
    }
}
